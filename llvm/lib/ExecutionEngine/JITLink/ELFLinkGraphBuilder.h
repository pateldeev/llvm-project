//===------- ELFLinkGraphBuilder.h - ELF LinkGraph builder ------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Generic ELF LinkGraph building code.
//
//===----------------------------------------------------------------------===//

#ifndef LIB_EXECUTIONENGINE_JITLINK_ELFLINKGRAPHBUILDER_H
#define LIB_EXECUTIONENGINE_JITLINK_ELFLINKGRAPHBUILDER_H

#include "llvm/ExecutionEngine/JITLink/JITLink.h"
#include "llvm/Object/ELF.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/FormatVariadic.h"

#define DEBUG_TYPE "jitlink"

namespace llvm {
namespace jitlink {

/// Common link-graph building code shared between all ELFFiles.
class ELFLinkGraphBuilderBase {
public:
  ELFLinkGraphBuilderBase(std::unique_ptr<LinkGraph> G) : G(std::move(G)) {}
  virtual ~ELFLinkGraphBuilderBase();

protected:
  static bool isDwarfSection(StringRef SectionName) {
    return llvm::is_contained(DwarfSectionNames, SectionName);
  }

  Section &getCommonSection() {
    if (!CommonSection)
      CommonSection =
          &G->createSection(CommonSectionName, MemProt::Read | MemProt::Write);
    return *CommonSection;
  }

  std::unique_ptr<LinkGraph> G;

private:
  static StringRef CommonSectionName;
  static ArrayRef<const char *> DwarfSectionNames;

  Section *CommonSection = nullptr;
};

/// Ling-graph building code that's specific to the given ELFT, but common
/// across all architectures.
template <typename ELFT>
class ELFLinkGraphBuilder : public ELFLinkGraphBuilderBase {
  using ELFFile = object::ELFFile<ELFT>;

public:
  ELFLinkGraphBuilder(const object::ELFFile<ELFT> &Obj, Triple TT,
                      StringRef FileName,
                      LinkGraph::GetEdgeKindNameFunction GetEdgeKindName);

  /// Attempt to construct and return the LinkGraph.
  Expected<std::unique_ptr<LinkGraph>> buildGraph();

  /// Call to derived class to handle relocations. These require
  /// architecture specific knowledge to map to JITLink edge kinds.
  virtual Error addRelocations() = 0;

protected:
  using ELFSectionIndex = unsigned;
  using ELFSymbolIndex = unsigned;

  bool isRelocatable() const {
    return Obj.getHeader().e_type == llvm::ELF::ET_REL;
  }

  void setGraphBlock(ELFSectionIndex SecIndex, Block *B) {
    assert(!GraphBlocks.count(SecIndex) && "Duplicate section at index");
    GraphBlocks[SecIndex] = B;
  }

  Block *getGraphBlock(ELFSectionIndex SecIndex) {
    auto I = GraphBlocks.find(SecIndex);
    if (I == GraphBlocks.end())
      return nullptr;
    return I->second;
  }

  void setGraphSymbol(ELFSymbolIndex SymIndex, Symbol &Sym) {
    assert(!GraphSymbols.count(SymIndex) && "Duplicate symbol at index");
    GraphSymbols[SymIndex] = &Sym;
  }

  Symbol *getGraphSymbol(ELFSymbolIndex SymIndex) {
    auto I = GraphSymbols.find(SymIndex);
    if (I == GraphSymbols.end())
      return nullptr;
    return I->second;
  }

  Expected<std::pair<Linkage, Scope>>
  getSymbolLinkageAndScope(const typename ELFT::Sym &Sym, StringRef Name);

  Error prepare();
  Error graphifySections();
  Error graphifySymbols();

  /// Traverse all matching relocation records in the given section. The handler
  /// function Func should be callable with this signature:
  ///   Error(const typename ELFT::Rela &,
  ///         const typename ELFT::Shdr &, Section &)
  ///
  template <typename RelocHandlerFunction>
  Error forEachRelocation(const typename ELFT::Shdr &RelSect,
                          RelocHandlerFunction &&Func,
                          bool ProcessDebugSections = false);

  /// Traverse all matching relocation records in the given section. Convenience
  /// wrapper to allow passing a member function for the handler.
  ///
  template <typename ClassT, typename RelocHandlerMethod>
  Error forEachRelocation(const typename ELFT::Shdr &RelSect, ClassT *Instance,
                          RelocHandlerMethod &&Method,
                          bool ProcessDebugSections = false) {
    return forEachRelocation(
        RelSect,
        [Instance, Method](const auto &Rel, const auto &Target, auto &GS) {
          return (Instance->*Method)(Rel, Target, GS);
        },
        ProcessDebugSections);
  }

  const ELFFile &Obj;

  typename ELFFile::Elf_Shdr_Range Sections;
  const typename ELFFile::Elf_Shdr *SymTabSec = nullptr;
  StringRef SectionStringTab;

  // Maps ELF section indexes to LinkGraph Blocks.
  // Only SHF_ALLOC sections will have graph blocks.
  DenseMap<ELFSectionIndex, Block *> GraphBlocks;
  DenseMap<ELFSymbolIndex, Symbol *> GraphSymbols;
  DenseMap<const typename ELFFile::Elf_Shdr *,
           ArrayRef<typename ELFFile::Elf_Word>>
      ShndxTables;
};

template <typename ELFT>
ELFLinkGraphBuilder<ELFT>::ELFLinkGraphBuilder(
    const ELFFile &Obj, Triple TT, StringRef FileName,
    LinkGraph::GetEdgeKindNameFunction GetEdgeKindName)
    : ELFLinkGraphBuilderBase(std::make_unique<LinkGraph>(
          FileName.str(), Triple(std::move(TT)), ELFT::Is64Bits ? 8 : 4,
          support::endianness(ELFT::TargetEndianness),
          std::move(GetEdgeKindName))),
      Obj(Obj) {
  LLVM_DEBUG(
      { dbgs() << "Created ELFLinkGraphBuilder for \"" << FileName << "\""; });
}

template <typename ELFT>
Expected<std::unique_ptr<LinkGraph>> ELFLinkGraphBuilder<ELFT>::buildGraph() {
  if (!isRelocatable())
    return make_error<JITLinkError>("Object is not a relocatable ELF file");

  if (auto Err = prepare())
    return std::move(Err);

  if (auto Err = graphifySections())
    return std::move(Err);

  if (auto Err = graphifySymbols())
    return std::move(Err);

  if (auto Err = addRelocations())
    return std::move(Err);

  return std::move(G);
}

template <typename ELFT>
Expected<std::pair<Linkage, Scope>>
ELFLinkGraphBuilder<ELFT>::getSymbolLinkageAndScope(
    const typename ELFT::Sym &Sym, StringRef Name) {
  Linkage L = Linkage::Strong;
  Scope S = Scope::Default;

  switch (Sym.getBinding()) {
  case ELF::STB_LOCAL:
    S = Scope::Local;
    break;
  case ELF::STB_GLOBAL:
    // Nothing to do here.
    break;
  case ELF::STB_WEAK:
  case ELF::STB_GNU_UNIQUE:
    L = Linkage::Weak;
    break;
  default:
    return make_error<StringError>(
        "Unrecognized symbol binding " +
            Twine(static_cast<int>(Sym.getBinding())) + " for " + Name,
        inconvertibleErrorCode());
  }

  switch (Sym.getVisibility()) {
  case ELF::STV_DEFAULT:
  case ELF::STV_PROTECTED:
    // FIXME: Make STV_DEFAULT symbols pre-emptible? This probably needs
    // Orc support.
    // Otherwise nothing to do here.
    break;
  case ELF::STV_HIDDEN:
    // Default scope -> Hidden scope. No effect on local scope.
    if (S == Scope::Default)
      S = Scope::Hidden;
    break;
  case ELF::STV_INTERNAL:
    return make_error<StringError>(
        "Unrecognized symbol visibility " +
            Twine(static_cast<int>(Sym.getVisibility())) + " for " + Name,
        inconvertibleErrorCode());
  }

  return std::make_pair(L, S);
}

template <typename ELFT> Error ELFLinkGraphBuilder<ELFT>::prepare() {
  LLVM_DEBUG(dbgs() << "  Preparing to build...\n");

  // Get the sections array.
  if (auto SectionsOrErr = Obj.sections())
    Sections = *SectionsOrErr;
  else
    return SectionsOrErr.takeError();

  // Get the section string table.
  if (auto SectionStringTabOrErr = Obj.getSectionStringTable(Sections))
    SectionStringTab = *SectionStringTabOrErr;
  else
    return SectionStringTabOrErr.takeError();

  // Get the SHT_SYMTAB section.
  for (auto &Sec : Sections) {
    if (Sec.sh_type == ELF::SHT_SYMTAB) {
      if (!SymTabSec)
        SymTabSec = &Sec;
      else
        return make_error<JITLinkError>("Multiple SHT_SYMTAB sections in " +
                                        G->getName());
    }

    // Extended table.
    if (Sec.sh_type == ELF::SHT_SYMTAB_SHNDX) {
      uint32_t SymtabNdx = Sec.sh_link;
      if (SymtabNdx >= Sections.size())
        return make_error<JITLinkError>("sh_link is out of bound");

      auto ShndxTable = Obj.getSHNDXTable(Sec);
      if (!ShndxTable)
        return ShndxTable.takeError();

      ShndxTables.insert({&Sections[SymtabNdx], *ShndxTable});
    }
  }

  return Error::success();
}

template <typename ELFT> Error ELFLinkGraphBuilder<ELFT>::graphifySections() {
  LLVM_DEBUG(dbgs() << "  Creating graph sections...\n");

  // For each section...
  for (ELFSectionIndex SecIndex = 0; SecIndex != Sections.size(); ++SecIndex) {

    auto &Sec = Sections[SecIndex];

    // Start by getting the section name.
    auto Name = Obj.getSectionName(Sec, SectionStringTab);
    if (!Name)
      return Name.takeError();

    // If the name indicates that it's a debug section then skip it: We don't
    // support those yet.
    if (isDwarfSection(*Name)) {
      LLVM_DEBUG({
        dbgs() << "    " << SecIndex << ": \"" << *Name
               << "\" is a debug section: "
                  "No graph section will be created.\n";
      });
      continue;
    }

    // Skip non-SHF_ALLOC sections
    if (!(Sec.sh_flags & ELF::SHF_ALLOC)) {
      LLVM_DEBUG({
        dbgs() << "    " << SecIndex << ": \"" << *Name
               << "\" is not an SHF_ALLOC section: "
                  "No graph section will be created.\n";
      });
      continue;
    }

    LLVM_DEBUG({
      dbgs() << "    " << SecIndex << ": Creating section for \"" << *Name
             << "\"\n";
    });

    // Get the section's memory protection flags.
    MemProt Prot;
    if (Sec.sh_flags & ELF::SHF_EXECINSTR)
      Prot = MemProt::Read | MemProt::Exec;
    else
      Prot = MemProt::Read | MemProt::Write;

    // Look for existing sections first.
    auto *GraphSec = G->findSectionByName(*Name);
    if (!GraphSec)
      GraphSec = &G->createSection(*Name, Prot);
    assert(GraphSec->getMemProt() == Prot && "MemProt should match");

    Block *B = nullptr;
    if (Sec.sh_type != ELF::SHT_NOBITS) {
      auto Data = Obj.template getSectionContentsAsArray<char>(Sec);
      if (!Data)
        return Data.takeError();

      B = &G->createContentBlock(*GraphSec, *Data,
                                 orc::ExecutorAddr(Sec.sh_addr),
                                 Sec.sh_addralign, 0);
    } else
      B = &G->createZeroFillBlock(*GraphSec, Sec.sh_size,
                                  orc::ExecutorAddr(Sec.sh_addr),
                                  Sec.sh_addralign, 0);

    setGraphBlock(SecIndex, B);
  }

  return Error::success();
}

template <typename ELFT> Error ELFLinkGraphBuilder<ELFT>::graphifySymbols() {
  LLVM_DEBUG(dbgs() << "  Creating graph symbols...\n");

  // No SYMTAB -- Bail out early.
  if (!SymTabSec)
    return Error::success();

  // Get the section content as a Symbols array.
  auto Symbols = Obj.symbols(SymTabSec);
  if (!Symbols)
    return Symbols.takeError();

  // Get the string table for this section.
  auto StringTab = Obj.getStringTableForSymtab(*SymTabSec, Sections);
  if (!StringTab)
    return StringTab.takeError();

  LLVM_DEBUG({
    StringRef SymTabName;

    if (auto SymTabNameOrErr = Obj.getSectionName(*SymTabSec, SectionStringTab))
      SymTabName = *SymTabNameOrErr;
    else {
      dbgs() << "Could not get ELF SHT_SYMTAB section name for logging: "
             << toString(SymTabNameOrErr.takeError()) << "\n";
      SymTabName = "<SHT_SYMTAB section with invalid name>";
    }

    dbgs() << "    Adding symbols from symtab section \"" << SymTabName
           << "\"\n";
  });

  for (ELFSymbolIndex SymIndex = 0; SymIndex != Symbols->size(); ++SymIndex) {
    auto &Sym = (*Symbols)[SymIndex];

    // Check symbol type.
    switch (Sym.getType()) {
    case ELF::STT_FILE:
      LLVM_DEBUG({
        if (auto Name = Sym.getName(*StringTab))
          dbgs() << "      " << SymIndex << ": Skipping STT_FILE symbol \""
                 << *Name << "\"\n";
        else {
          dbgs() << "Could not get STT_FILE symbol name: "
                 << toString(Name.takeError()) << "\n";
          dbgs() << "     " << SymIndex
                 << ": Skipping STT_FILE symbol with invalid name\n";
        }
      });
      continue;
      break;
    }

    // Get the symbol name.
    auto Name = Sym.getName(*StringTab);
    if (!Name)
      return Name.takeError();

    // Handle common symbols specially.
    if (Sym.isCommon()) {
      Symbol &GSym = G->addDefinedSymbol(
          G->createZeroFillBlock(getCommonSection(), Sym.st_size,
                                 orc::ExecutorAddr(), Sym.getValue(), 0),
          0, *Name, Sym.st_size, Linkage::Strong, Scope::Default, false, false);
      setGraphSymbol(SymIndex, GSym);
      continue;
    }

    if (Sym.isDefined() &&
        (Sym.getType() == ELF::STT_NOTYPE || Sym.getType() == ELF::STT_FUNC ||
         Sym.getType() == ELF::STT_OBJECT ||
         Sym.getType() == ELF::STT_SECTION || Sym.getType() == ELF::STT_TLS)) {

      // Map Visibility and Binding to Scope and Linkage:
      Linkage L;
      Scope S;
      if (auto LSOrErr = getSymbolLinkageAndScope(Sym, *Name))
        std::tie(L, S) = *LSOrErr;
      else
        return LSOrErr.takeError();

      // Handle extended tables.
      unsigned Shndx = Sym.st_shndx;
      if (Shndx == ELF::SHN_XINDEX) {
        auto ShndxTable = ShndxTables.find(SymTabSec);
        if (ShndxTable == ShndxTables.end())
          continue;
        auto NdxOrErr = object::getExtendedSymbolTableIndex<ELFT>(
            Sym, SymIndex, ShndxTable->second);
        if (!NdxOrErr)
          return NdxOrErr.takeError();
        Shndx = *NdxOrErr;
      }
      if (auto *B = getGraphBlock(Shndx)) {
        LLVM_DEBUG({
          dbgs() << "      " << SymIndex
                 << ": Creating defined graph symbol for ELF symbol \"" << *Name
                 << "\"\n";
        });

        // In RISCV, temporary symbols (Used to generate dwarf, eh_frame
        // sections...) will appear in object code's symbol table, and LLVM does
        // not use names on these temporary symbols (RISCV gnu toolchain uses
        // names on these temporary symbols). If the symbol is unnamed, add an
        // anonymous symbol.
        auto &GSym =
            Name->empty()
                ? G->addAnonymousSymbol(*B, Sym.getValue(), Sym.st_size,
                                        false, false)
                : G->addDefinedSymbol(*B, Sym.getValue(), *Name, Sym.st_size, L,
                                      S, Sym.getType() == ELF::STT_FUNC, false);
        setGraphSymbol(SymIndex, GSym);
      }
    } else if (Sym.isUndefined() && Sym.isExternal()) {
      LLVM_DEBUG({
        dbgs() << "      " << SymIndex
               << ": Creating external graph symbol for ELF symbol \"" << *Name
               << "\"\n";
      });

      if (Sym.getBinding() != ELF::STB_GLOBAL &&
          Sym.getBinding() != ELF::STB_WEAK)
        return make_error<StringError>(
            "Invalid symbol binding " +
                Twine(static_cast<int>(Sym.getBinding())) +
                " for external symbol " + *Name,
            inconvertibleErrorCode());

      // If L is Linkage::Weak that means this is a weakly referenced symbol.
      auto &GSym = G->addExternalSymbol(*Name, Sym.st_size,
                                        Sym.getBinding() == ELF::STB_WEAK);
      setGraphSymbol(SymIndex, GSym);
    } else {
      LLVM_DEBUG({
        dbgs() << "      " << SymIndex
               << ": Not creating graph symbol for ELF symbol \"" << *Name
               << "\" with unrecognized type\n";
      });
    }
  }

  return Error::success();
}

template <typename ELFT>
template <typename RelocHandlerFunction>
Error ELFLinkGraphBuilder<ELFT>::forEachRelocation(
    const typename ELFT::Shdr &RelSect, RelocHandlerFunction &&Func,
    bool ProcessDebugSections) {

  // Only look into sections that store relocation entries.
  if (RelSect.sh_type != ELF::SHT_RELA && RelSect.sh_type != ELF::SHT_REL)
    return Error::success();

  // sh_info contains the section header index of the target (FixupSection),
  // which is the section to which all relocations in RelSect apply.
  auto FixupSection = Obj.getSection(RelSect.sh_info);
  if (!FixupSection)
    return FixupSection.takeError();

  // Target sections have names in valid ELF object files.
  Expected<StringRef> Name = Obj.getSectionName(**FixupSection);
  if (!Name)
    return Name.takeError();
  LLVM_DEBUG(dbgs() << "  " << *Name << ":\n");

  // Consider skipping these relocations.
  if (!ProcessDebugSections && isDwarfSection(*Name)) {
    LLVM_DEBUG(dbgs() << "    skipped (dwarf section)\n\n");
    return Error::success();
  }

  // Lookup the link-graph node corresponding to the target section name.
  auto *BlockToFix = getGraphBlock(RelSect.sh_info);
  if (!BlockToFix)
    return make_error<StringError>(
        "Refencing a section that wasn't added to the graph: " + *Name,
        inconvertibleErrorCode());

  auto RelEntries = Obj.relas(RelSect);
  if (!RelEntries)
    return RelEntries.takeError();

  // Let the callee process relocation entries one by one.
  for (const typename ELFT::Rela &R : *RelEntries)
    if (Error Err = Func(R, **FixupSection, *BlockToFix))
      return Err;

  LLVM_DEBUG(dbgs() << "\n");
  return Error::success();
}

} // end namespace jitlink
} // end namespace llvm

#undef DEBUG_TYPE

#endif // LIB_EXECUTIONENGINE_JITLINK_ELFLINKGRAPHBUILDER_H
