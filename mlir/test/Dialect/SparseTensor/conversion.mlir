// RUN: mlir-opt %s --sparse-tensor-conversion --canonicalize --cse | FileCheck %s

#SparseVector = #sparse_tensor.encoding<{
  dimLevelType = ["compressed"]
}>

#SparseVector64 = #sparse_tensor.encoding<{
  dimLevelType = ["compressed"],
  pointerBitWidth = 64,
  indexBitWidth = 64
}>

#SparseVector32 = #sparse_tensor.encoding<{
  dimLevelType = ["compressed"],
  pointerBitWidth = 32,
  indexBitWidth = 32
}>

#CSR = #sparse_tensor.encoding<{
  dimLevelType = ["dense", "compressed"]
}>

#CSC = #sparse_tensor.encoding<{
  dimLevelType = ["dense", "compressed"],
  dimOrdering = affine_map<(i,j) -> (j,i)>
}>

#SparseTensor = #sparse_tensor.encoding<{
  dimLevelType = ["dense", "compressed", "compressed"],
  dimOrdering = affine_map<(i,j,k) -> (k,i,j)>
}>

// CHECK-LABEL: func @sparse_nop(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>) -> !llvm.ptr<i8>
//       CHECK: return %[[A]] : !llvm.ptr<i8>
func.func @sparse_nop(%arg0: tensor<?xf64, #SparseVector>) -> tensor<?xf64, #SparseVector> {
  return %arg0 : tensor<?xf64, #SparseVector>
}

// CHECK-LABEL: func @sparse_dim1d(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 0 : index
//       CHECK: %[[D:.*]] = call @sparseDimSize(%[[A]], %[[C]])
//       CHECK: return %[[D]] : index
func.func @sparse_dim1d(%arg0: tensor<?xf64, #SparseVector>) -> index {
  %c = arith.constant 0 : index
  %0 = tensor.dim %arg0, %c : tensor<?xf64, #SparseVector>
  return %0 : index
}

// CHECK-LABEL: func @sparse_dim3d(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 2 : index
//       CHECK: %[[D:.*]] = call @sparseDimSize(%[[A]], %[[C]])
//       CHECK: return %[[D]] : index
func.func @sparse_dim3d(%arg0: tensor<?x?x?xf64, #SparseTensor>) -> index {
  // Querying for dimension 1 in the tensor type needs to be
  // permuted into querying for dimension 2 in the stored sparse
  // tensor scheme, since the latter honors the dimOrdering.
  %c = arith.constant 1 : index
  %0 = tensor.dim %arg0, %c : tensor<?x?x?xf64, #SparseTensor>
  return %0 : index
}

// CHECK-LABEL: func @sparse_dim3d_const(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 20 : index
//       CHECK: return %[[C]] : index
func.func @sparse_dim3d_const(%arg0: tensor<10x20x30xf64, #SparseTensor>) -> index {
  // Querying for dimension 1 in the tensor type can be directly
  // folded into the right value (even though it corresponds
  // to dimension 2 in the stored sparse tensor scheme).
  %c = arith.constant 1 : index
  %0 = tensor.dim %arg0, %c : tensor<10x20x30xf64, #SparseTensor>
  return %0 : index
}

// CHECK-LABEL: func @sparse_new1d(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>) -> !llvm.ptr<i8>
//   CHECK-DAG: %[[FromFile:.*]] = arith.constant 1 : i32
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<1xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<1xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<1xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<1xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<1xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<1xindex> to memref<?xindex>
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[FromFile]], %[[A]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_new1d(%arg0: !llvm.ptr<i8>) -> tensor<128xf64, #SparseVector> {
  %0 = sparse_tensor.new %arg0 : !llvm.ptr<i8> to tensor<128xf64, #SparseVector>
  return %0 : tensor<128xf64, #SparseVector>
}

// CHECK-LABEL: func @sparse_new2d(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>) -> !llvm.ptr<i8>
//   CHECK-DAG: %[[FromFile:.*]] = arith.constant 1 : i32
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<2xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<2xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<2xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<2xindex> to memref<?xindex>
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[FromFile]], %[[A]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_new2d(%arg0: !llvm.ptr<i8>) -> tensor<?x?xf32, #CSR> {
  %0 = sparse_tensor.new %arg0 : !llvm.ptr<i8> to tensor<?x?xf32, #CSR>
  return %0 : tensor<?x?xf32, #CSR>
}

// CHECK-LABEL: func @sparse_new3d(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>) -> !llvm.ptr<i8>
//   CHECK-DAG: %[[FromFile:.*]] = arith.constant 1 : i32
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<3xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<3xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<3xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<3xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<3xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<3xindex> to memref<?xindex>
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[FromFile]], %[[A]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_new3d(%arg0: !llvm.ptr<i8>) -> tensor<?x?x?xf32, #SparseTensor> {
  %0 = sparse_tensor.new %arg0 : !llvm.ptr<i8> to tensor<?x?x?xf32, #SparseTensor>
  return %0 : tensor<?x?x?xf32, #SparseTensor>
}

// CHECK-LABEL: func @sparse_init(
//  CHECK-SAME: %[[I:.*]]: index,
//  CHECK-SAME: %[[J:.*]]: index) -> !llvm.ptr<i8>
//   CHECK-DAG: %[[Empty:.*]] = arith.constant 0 : i32
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: %[[C1:.*]] = arith.constant 1 : index
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<2xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<2xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<2xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<2xindex> to memref<?xindex>
//   CHECK-DAG: memref.store %[[I]], %[[Q]][%[[C0]]] : memref<2xindex>
//   CHECK-DAG: memref.store %[[J]], %[[Q]][%[[C1]]] : memref<2xindex>
//       CHECK: %[[NP:.*]] = llvm.mlir.null : !llvm.ptr<i8>
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[Empty]], %[[NP]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_init(%arg0: index, %arg1: index) -> tensor<?x?xf64, #CSR> {
  %0 = bufferization.alloc_tensor(%arg0, %arg1) : tensor<?x?xf64, #CSR>
  %1 = sparse_tensor.load %0 : tensor<?x?xf64, #CSR>
  return %1 : tensor<?x?xf64, #CSR>
}

// CHECK-LABEL: func @sparse_release(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: call @delSparseTensor(%[[A]]) : (!llvm.ptr<i8>) -> ()
//       CHECK: return
func.func @sparse_release(%arg0: tensor<128xf64, #SparseVector>) {
  bufferization.dealloc_tensor %arg0 : tensor<128xf64, #SparseVector>
  return
}

// CHECK-LABEL: func @sparse_nop_convert(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>) -> !llvm.ptr<i8>
//       CHECK: return %[[A]] : !llvm.ptr<i8>
func.func @sparse_nop_convert(%arg0: tensor<64xf32, #SparseVector>) -> tensor<64xf32, #SparseVector> {
  %0 = sparse_tensor.convert %arg0 : tensor<64xf32, #SparseVector> to tensor<64xf32, #SparseVector>
  return %0 : tensor<64xf32, #SparseVector>
}

// CHECK-LABEL: func @sparse_hidden_nop_cast(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>) -> !llvm.ptr<i8>
//       CHECK: return %[[A]] : !llvm.ptr<i8>
func.func @sparse_hidden_nop_cast(%arg0: tensor<32xf32, #SparseVector>) -> tensor<?xf32, #SparseVector> {
  %0 = sparse_tensor.convert %arg0 : tensor<32xf32, #SparseVector> to tensor<?xf32, #SparseVector>
  return %0 : tensor<?xf32, #SparseVector>
}

// CHECK-LABEL: func @sparse_nop_cast(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>) -> !llvm.ptr<i8>
//       CHECK: return %[[A]] : !llvm.ptr<i8>
func.func @sparse_nop_cast(%arg0: tensor<64xf32, #SparseVector>) -> tensor<?xf32, #SparseVector> {
  %0 = tensor.cast %arg0 : tensor<64xf32, #SparseVector> to tensor<?xf32, #SparseVector>
  return %0 : tensor<?xf32, #SparseVector>
}

// CHECK-LABEL: func @sparse_convert_1d(
//  CHECK-SAME: %[[A:.*]]: tensor<?xi32>) -> !llvm.ptr<i8> {
//   CHECK-DAG: %[[EmptyCOO:.*]] = arith.constant 4 : i32
//   CHECK-DAG: %[[FromCOO:.*]] = arith.constant 2 : i32
//   CHECK-DAG: %[[I0:.*]] = arith.constant 0 : i32
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: %[[C1:.*]] = arith.constant 1 : index
//   CHECK-DAG: %[[U:.*]] = tensor.dim %[[A]], %[[C0]] : tensor<?xi32>
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<1xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<1xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<1xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<1xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<1xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<1xindex> to memref<?xindex>
//       CHECK: %[[NP:.*]] = llvm.mlir.null : !llvm.ptr<i8>
//       CHECK: %[[C:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[EmptyCOO]], %[[NP]])
//       CHECK: %[[M:.*]] = memref.alloca() : memref<1xindex>
//       CHECK: %[[T:.*]] = memref.cast %[[M]] : memref<1xindex> to memref<?xindex>
//       CHECK: %[[BUF:.*]] = memref.alloca() : memref<i32>
//       CHECK: scf.for %[[I:.*]] = %[[C0]] to %[[U]] step %[[C1]] {
//       CHECK:   %[[E:.*]] = tensor.extract %[[A]][%[[I]]] : tensor<?xi32>
//       CHECK:   %[[N:.*]] = arith.cmpi ne, %[[E]], %[[I0]] : i32
//       CHECK:   scf.if %[[N]] {
//       CHECK:     memref.store %[[I]], %[[M]][%[[C0]]] : memref<1xindex>
//       CHECK:     memref.store %[[E]], %[[BUF]][] : memref<i32>
//       CHECK:     call @addEltI32(%[[C]], %[[BUF]], %[[T]], %[[Z]])
//       CHECK:   }
//       CHECK: }
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[FromCOO]], %[[C]])
//       CHECK: call @delSparseTensorCOOI32(%[[C]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_convert_1d(%arg0: tensor<?xi32>) -> tensor<?xi32, #SparseVector> {
  %0 = sparse_tensor.convert %arg0 : tensor<?xi32> to tensor<?xi32, #SparseVector>
  return %0 : tensor<?xi32, #SparseVector>
}

// CHECK-LABEL: func @sparse_convert_complex(
//  CHECK-SAME: %[[A:.*]]: tensor<100xcomplex<f64>>) -> !llvm.ptr<i8> {
//   CHECK-DAG: %[[CC:.*]] = complex.constant [0.000000e+00, 0.000000e+00] : complex<f64>
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: %[[C1:.*]] = arith.constant 1 : index
//   CHECK-DAG: %[[C100:.*]] = arith.constant 100 : index
//       CHECK: scf.for %[[I:.*]] = %[[C0]] to %[[C100]] step %[[C1]] {
//       CHECK:   %[[E:.*]] = tensor.extract %[[A]][%[[I]]] : tensor<100xcomplex<f64>>
//       CHECK:   %[[N:.*]] = complex.neq %[[E]], %[[CC]] : complex<f64>
//       CHECK:   scf.if %[[N]] {
//       CHECK:     memref.store %[[I]], %{{.*}}[%[[C0]]] : memref<1xindex>
//       CHECK:     call @addEltC64
//       CHECK:   }
//       CHECK: }
//       CHECK: %[[T:.*]] = call @newSparseTensor
//       CHECK: call @delSparseTensorCOOC64
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_convert_complex(%arg0: tensor<100xcomplex<f64>>) -> tensor<100xcomplex<f64>, #SparseVector> {
  %0 = sparse_tensor.convert %arg0 : tensor<100xcomplex<f64>> to tensor<100xcomplex<f64>, #SparseVector>
  return %0 : tensor<100xcomplex<f64>, #SparseVector>
}

// CHECK-LABEL: func @sparse_convert_1d_ss(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//   CHECK-DAG: %[[SparseToSparse:.*]] = arith.constant 3 : i32
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<1xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<1xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<1xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<1xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<1xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<1xindex> to memref<?xindex>
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[SparseToSparse]], %[[A]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_convert_1d_ss(%arg0: tensor<?xf32, #SparseVector64>) -> tensor<?xf32, #SparseVector32> {
  %0 = sparse_tensor.convert %arg0 : tensor<?xf32, #SparseVector64> to tensor<?xf32, #SparseVector32>
  return %0 : tensor<?xf32, #SparseVector32>
}

// CHECK-LABEL: func @sparse_convert_2d(
//  CHECK-SAME: %[[A:.*]]: tensor<2x4xf64>) -> !llvm.ptr<i8>
//   CHECK-DAG: %[[EmptyCOO:.*]] = arith.constant 4 : i32
//   CHECK-DAG: %[[FromCOO:.*]] = arith.constant 2 : i32
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: %[[C1:.*]] = arith.constant 1 : index
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<2xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<2xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<2xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<2xindex> to memref<?xindex>
//       CHECK: %[[NP:.*]] = llvm.mlir.null : !llvm.ptr<i8>
//       CHECK: %[[C:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[EmptyCOO]], %[[NP]])
//       CHECK: %[[M:.*]] = memref.alloca() : memref<2xindex>
//       CHECK: %[[T:.*]] = memref.cast %[[M]] : memref<2xindex> to memref<?xindex>
//       CHECK: %[[BUF:.*]] = memref.alloca() : memref<f64>
//       CHECK: scf.for %[[I:.*]] = %[[C0]] to %{{.*}} step %[[C1]] {
//       CHECK:   scf.for %[[J:.*]] = %[[C0]] to %{{.*}} step %[[C1]] {
//       CHECK:     %[[E:.*]] = tensor.extract %[[A]][%[[I]], %[[J]]] : tensor<2x4xf64>
//       CHECK:     memref.store %[[I]], %[[M]][%[[C0]]] : memref<2xindex>
//       CHECK:     memref.store %[[J]], %[[M]][%[[C1]]] : memref<2xindex>
//       CHECK:     memref.store %[[E]], %[[BUF]][] : memref<f64>
//       CHECK:     call @addEltF64(%[[C]], %[[BUF]], %[[T]], %[[Z]])
//       CHECK:   }
//       CHECK: }
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[FromCOO]], %[[C]])
//       CHECK: call @delSparseTensorCOOF64(%[[C]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_convert_2d(%arg0: tensor<2x4xf64>) -> tensor<2x4xf64, #CSR> {
  %0 = sparse_tensor.convert %arg0 : tensor<2x4xf64> to tensor<2x4xf64, #CSR>
  return %0 : tensor<2x4xf64, #CSR>
}

// CHECK-LABEL: func @sparse_constant() -> !llvm.ptr<i8> {
//   CHECK-DAG: %[[EmptyCOO:.*]] = arith.constant 4 : i32
//   CHECK-DAG: %[[FromCOO:.*]] = arith.constant 2 : i32
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: %[[C1:.*]] = arith.constant 1 : index
//   CHECK-DAG: %[[C2:.*]] = arith.constant 2 : index
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<2xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<2xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<2xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<2xindex> to memref<?xindex>
//       CHECK: %[[NP:.*]] = llvm.mlir.null : !llvm.ptr<i8>
//       CHECK: %[[C:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[EmptyCOO]], %[[NP]])
//       CHECK: %[[M:.*]] = memref.alloca() : memref<2xindex>
//       CHECK: %[[N:.*]] = memref.cast %[[M]] : memref<2xindex> to memref<?xindex>
//       CHECK: %[[BUF:.*]] = memref.alloca() : memref<f32>
//       CHECK: scf.for %[[I:.*]] = %[[C0]] to %[[C2]] step %[[C1]] {
//       CHECK:   memref.store %{{.*}}, %[[M]][%[[C0]]] : memref<2xindex>
//       CHECK:   memref.store %{{.*}}, %[[M]][%[[C1]]] : memref<2xindex>
//       CHECK:   %[[V:.*]] = tensor.extract %{{.*}}[%[[I]]] : tensor<2xf32>
//       CHECK:   memref.store %[[V]], %[[BUF]][] : memref<f32>
//       CHECK:   call @addEltF32(%{{.*}}, %[[BUF]], %[[N]], %{{.*}})
//       CHECK: }
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[FromCOO]], %[[C]])
//       CHECK: call @delSparseTensorCOOF32(%[[C]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_constant() -> tensor<8x7xf32, #CSR>{
  // Initialize a tensor.
  %0 = arith.constant sparse<[[0, 0], [1, 6]], [1.0, 5.0]> : tensor<8x7xf32>
  // Convert the tensor to a sparse tensor.
  %1 = sparse_tensor.convert %0 : tensor<8x7xf32> to tensor<8x7xf32, #CSR>
  return %1 : tensor<8x7xf32, #CSR>
}

// CHECK-LABEL: func @sparse_convert_3d(
//  CHECK-SAME: %[[A:.*]]: tensor<?x?x?xf64>) -> !llvm.ptr<i8>
//   CHECK-DAG: %[[EmptyCOO:.*]] = arith.constant 4 : i32
//   CHECK-DAG: %[[FromCOO:.*]] = arith.constant 2 : i32
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: %[[C1:.*]] = arith.constant 1 : index
//   CHECK-DAG: %[[C2:.*]] = arith.constant 2 : index
//   CHECK-DAG: %[[U1:.*]] = tensor.dim %[[A]], %[[C0]] : tensor<?x?x?xf64>
//   CHECK-DAG: %[[U2:.*]] = tensor.dim %[[A]], %[[C1]] : tensor<?x?x?xf64>
//   CHECK-DAG: %[[U3:.*]] = tensor.dim %[[A]], %[[C2]] : tensor<?x?x?xf64>
//   CHECK-DAG: %[[P:.*]] = memref.alloca() : memref<3xi8>
//   CHECK-DAG: %[[Q:.*]] = memref.alloca() : memref<3xindex>
//   CHECK-DAG: %[[R:.*]] = memref.alloca() : memref<3xindex>
//   CHECK-DAG: %[[X:.*]] = memref.cast %[[P]] : memref<3xi8> to memref<?xi8>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[Q]] : memref<3xindex> to memref<?xindex>
//   CHECK-DAG: %[[Z:.*]] = memref.cast %[[R]] : memref<3xindex> to memref<?xindex>
//       CHECK: %[[NP:.*]] = llvm.mlir.null : !llvm.ptr<i8>
//       CHECK: %[[C:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[EmptyCOO]], %[[NP]])
//       CHECK: %[[M:.*]] = memref.alloca() : memref<3xindex>
//       CHECK: %[[N:.*]] = memref.cast %[[M]] : memref<3xindex> to memref<?xindex>
//       CHECK: %[[BUF:.*]] = memref.alloca() : memref<f64>
//       CHECK: scf.for %[[I:.*]] = %[[C0]] to %[[U1]] step %[[C1]] {
//       CHECK:   scf.for %[[J:.*]] = %[[C0]] to %[[U2]] step %[[C1]] {
//       CHECK:     scf.for %[[K:.*]] = %[[C0]] to %[[U3]] step %[[C1]] {
//       CHECK:       %[[E:.*]] = tensor.extract %[[A]][%[[I]], %[[J]], %[[K]]] : tensor<?x?x?xf64>
//       CHECK:       memref.store %[[I]], %[[M]][%[[C0]]] : memref<3xindex>
//       CHECK:       memref.store %[[J]], %[[M]][%[[C1]]] : memref<3xindex>
//       CHECK:       memref.store %[[K]], %[[M]][%[[C2]]] : memref<3xindex>
//       CHECK:       memref.store %[[E]], %[[BUF]][] : memref<f64>
//       CHECK:       call @addEltF64(%[[C]], %[[BUF]], %[[N]], %[[Z]])
//       CHECK:     }
//       CHECK:   }
//       CHECK: }
//       CHECK: %[[T:.*]] = call @newSparseTensor(%[[X]], %[[Y]], %[[Z]], %{{.*}}, %{{.*}}, %{{.*}}, %[[FromCOO]], %[[C]])
//       CHECK: call @delSparseTensorCOOF64(%[[C]])
//       CHECK: return %[[T]] : !llvm.ptr<i8>
func.func @sparse_convert_3d(%arg0: tensor<?x?x?xf64>) -> tensor<?x?x?xf64, #SparseTensor> {
  %0 = sparse_tensor.convert %arg0 : tensor<?x?x?xf64> to tensor<?x?x?xf64, #SparseTensor>
  return %0 : tensor<?x?x?xf64, #SparseTensor>
}

// CHECK-LABEL: func @sparse_pointers(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 0 : index
//       CHECK: %[[T:.*]] = call @sparsePointers0(%[[A]], %[[C]]) : (!llvm.ptr<i8>, index) -> memref<?xindex>
//       CHECK: return %[[T]] : memref<?xindex>
func.func @sparse_pointers(%arg0: tensor<128xf64, #SparseVector>) -> memref<?xindex> {
  %0 = sparse_tensor.pointers %arg0 { dimension = 0 : index } : tensor<128xf64, #SparseVector> to memref<?xindex>
  return %0 : memref<?xindex>
}

// CHECK-LABEL: func @sparse_pointers64(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 0 : index
//       CHECK: %[[T:.*]] = call @sparsePointers64(%[[A]], %[[C]]) : (!llvm.ptr<i8>, index) -> memref<?xi64>
//       CHECK: return %[[T]] : memref<?xi64>
func.func @sparse_pointers64(%arg0: tensor<128xf64, #SparseVector64>) -> memref<?xi64> {
  %0 = sparse_tensor.pointers %arg0 { dimension = 0 : index } : tensor<128xf64, #SparseVector64> to memref<?xi64>
  return %0 : memref<?xi64>
}

// CHECK-LABEL: func @sparse_pointers32(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 0 : index
//       CHECK: %[[T:.*]] = call @sparsePointers32(%[[A]], %[[C]]) : (!llvm.ptr<i8>, index) -> memref<?xi32>
//       CHECK: return %[[T]] : memref<?xi32>
func.func @sparse_pointers32(%arg0: tensor<128xf64, #SparseVector32>) -> memref<?xi32> {
  %0 = sparse_tensor.pointers %arg0 { dimension = 0 : index } : tensor<128xf64, #SparseVector32> to memref<?xi32>
  return %0 : memref<?xi32>
}

// CHECK-LABEL: func @sparse_indices(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 0 : index
//       CHECK: %[[T:.*]] = call @sparseIndices0(%[[A]], %[[C]]) : (!llvm.ptr<i8>, index) -> memref<?xindex>
//       CHECK: return %[[T]] : memref<?xindex>
func.func @sparse_indices(%arg0: tensor<128xf64, #SparseVector>) -> memref<?xindex> {
  %0 = sparse_tensor.indices %arg0 { dimension = 0 : index } : tensor<128xf64, #SparseVector> to memref<?xindex>
  return %0 : memref<?xindex>
}

// CHECK-LABEL: func @sparse_indices64(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 0 : index
//       CHECK: %[[T:.*]] = call @sparseIndices64(%[[A]], %[[C]]) : (!llvm.ptr<i8>, index) -> memref<?xi64>
//       CHECK: return %[[T]] : memref<?xi64>
func.func @sparse_indices64(%arg0: tensor<128xf64, #SparseVector64>) -> memref<?xi64> {
  %0 = sparse_tensor.indices %arg0 { dimension = 0 : index } : tensor<128xf64, #SparseVector64> to memref<?xi64>
  return %0 : memref<?xi64>
}

// CHECK-LABEL: func @sparse_indices32(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[C:.*]] = arith.constant 0 : index
//       CHECK: %[[T:.*]] = call @sparseIndices32(%[[A]], %[[C]]) : (!llvm.ptr<i8>, index) -> memref<?xi32>
//       CHECK: return %[[T]] : memref<?xi32>
func.func @sparse_indices32(%arg0: tensor<128xf64, #SparseVector32>) -> memref<?xi32> {
  %0 = sparse_tensor.indices %arg0 { dimension = 0 : index } : tensor<128xf64, #SparseVector32> to memref<?xi32>
  return %0 : memref<?xi32>
}

// CHECK-LABEL: func @sparse_valuesf64(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[T:.*]] = call @sparseValuesF64(%[[A]]) : (!llvm.ptr<i8>) -> memref<?xf64>
//       CHECK: return %[[T]] : memref<?xf64>
func.func @sparse_valuesf64(%arg0: tensor<128xf64, #SparseVector>) -> memref<?xf64> {
  %0 = sparse_tensor.values %arg0 : tensor<128xf64, #SparseVector> to memref<?xf64>
  return %0 : memref<?xf64>
}

// CHECK-LABEL: func @sparse_valuesf32(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[T:.*]] = call @sparseValuesF32(%[[A]]) : (!llvm.ptr<i8>) -> memref<?xf32>
//       CHECK: return %[[T]] : memref<?xf32>
func.func @sparse_valuesf32(%arg0: tensor<128xf32, #SparseVector>) -> memref<?xf32> {
  %0 = sparse_tensor.values %arg0: tensor<128xf32, #SparseVector> to memref<?xf32>
  return %0 : memref<?xf32>
}

// CHECK-LABEL: func @sparse_valuesi32(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[T:.*]] = call @sparseValuesI32(%[[A]]) : (!llvm.ptr<i8>) -> memref<?xi32>
//       CHECK: return %[[T]] : memref<?xi32>
func.func @sparse_valuesi32(%arg0: tensor<128xi32, #SparseVector>) -> memref<?xi32> {
  %0 = sparse_tensor.values %arg0: tensor<128xi32, #SparseVector> to memref<?xi32>
  return %0 : memref<?xi32>
}

// CHECK-LABEL: func @sparse_valuesi16(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[T:.*]] = call @sparseValuesI16(%[[A]]) : (!llvm.ptr<i8>) -> memref<?xi16>
//       CHECK: return %[[T]] : memref<?xi16>
func.func @sparse_valuesi16(%arg0: tensor<128xi16, #SparseVector>) -> memref<?xi16> {
  %0 = sparse_tensor.values %arg0: tensor<128xi16, #SparseVector> to memref<?xi16>
  return %0 : memref<?xi16>
}

// CHECK-LABEL: func @sparse_valuesi8(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>)
//       CHECK: %[[T:.*]] = call @sparseValuesI8(%[[A]]) : (!llvm.ptr<i8>) -> memref<?xi8>
//       CHECK: return %[[T]] : memref<?xi8>
func.func @sparse_valuesi8(%arg0: tensor<128xi8, #SparseVector>) -> memref<?xi8> {
  %0 = sparse_tensor.values %arg0: tensor<128xi8, #SparseVector> to memref<?xi8>
  return %0 : memref<?xi8>
}

// CHECK-LABEL: func @sparse_reconstruct(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>
//       CHECK: return %[[A]] : !llvm.ptr<i8>
func.func @sparse_reconstruct(%arg0: tensor<128xf32, #SparseVector>) -> tensor<128xf32, #SparseVector> {
  %0 = sparse_tensor.load %arg0 : tensor<128xf32, #SparseVector>
  return %0 : tensor<128xf32, #SparseVector>
}

// CHECK-LABEL: func @sparse_reconstruct_ins(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>
//       CHECK: call @endInsert(%[[A]]) : (!llvm.ptr<i8>) -> ()
//       CHECK: return %[[A]] : !llvm.ptr<i8>
func.func @sparse_reconstruct_ins(%arg0: tensor<128xf32, #SparseVector>) -> tensor<128xf32, #SparseVector> {
  %0 = sparse_tensor.load %arg0 hasInserts : tensor<128xf32, #SparseVector>
  return %0 : tensor<128xf32, #SparseVector>
}

// CHECK-LABEL: func @sparse_insert(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>,
//  CHECK-SAME: %[[B:.*]]: index,
//  CHECK-SAME: %[[C:.*]]: f32) {
//   CHECK-DAG: %[[M:.*]] = memref.alloca() : memref<1xindex>
//   CHECK-DAG: %[[V:.*]] = memref.alloca() : memref<f32>
//   CHECK-DAG: %[[MC:.*]] = memref.cast %[[M]] : memref<1xindex> to memref<?xindex>
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: memref.store %[[B]], %[[M]][%[[C0]]] : memref<1xindex>
//   CHECK-DAG: memref.store %[[C]], %[[V]][] : memref<f32>
//       CHECK: call @lexInsertF32(%[[A]], %[[MC]], %[[V]]) : (!llvm.ptr<i8>, memref<?xindex>, memref<f32>) -> ()
//       CHECK: return
func.func @sparse_insert(%arg0: tensor<128xf32, #SparseVector>,
                         %arg1: index,
                         %arg2: f32) {
  sparse_tensor.insert %arg2 into %arg0[%arg1] : tensor<128xf32, #SparseVector>
  return
}

// CHECK-LABEL: func @sparse_expansion1()
//       CHECK: %[[N:.*]] = call @newSparseTensor
//       CHECK: %[[A:.*]] = memref.alloc() : memref<8xf64>
//       CHECK: %[[B:.*]] = memref.alloc() : memref<8xi1>
//       CHECK: %[[C:.*]] = memref.alloc() : memref<8xindex>
//       CHECK: %[[D:.*]] = memref.cast %[[C]] : memref<8xindex> to memref<?xindex>
//   CHECK-DAG: linalg.fill ins(%{{.*}} : f64) outs(%[[A]] : memref<8xf64>)
//   CHECK-DAG: linalg.fill ins(%{{.*}} : i1) outs(%[[B]] : memref<8xi1>)
//       CHECK: return %[[D]] : memref<?xindex>
func.func @sparse_expansion1() -> memref<?xindex> {
  %0 = bufferization.alloc_tensor() : tensor<4x8xf64, #CSR>
  %values, %filled, %added, %count = sparse_tensor.expand %0
    : tensor<4x8xf64, #CSR> to memref<?xf64>, memref<?xi1>, memref<?xindex>
  return %added : memref<?xindex>
}

// CHECK-LABEL: func @sparse_expansion2()
//       CHECK: %[[N:.*]] = call @newSparseTensor
//       CHECK: %[[A:.*]] = memref.alloc() : memref<4xf64>
//       CHECK: %[[B:.*]] = memref.alloc() : memref<4xi1>
//       CHECK: %[[C:.*]] = memref.alloc() : memref<4xindex>
//       CHECK: %[[D:.*]] = memref.cast %[[C]] : memref<4xindex> to memref<?xindex>
//   CHECK-DAG: linalg.fill ins(%{{.*}} : f64) outs(%[[A]] : memref<4xf64>)
//   CHECK-DAG: linalg.fill ins(%{{.*}} : i1) outs(%[[B]] : memref<4xi1>)
//       CHECK: return %[[D]] : memref<?xindex>
func.func @sparse_expansion2() -> memref<?xindex> {
  %0 = bufferization.alloc_tensor() : tensor<4x8xf64, #CSC>
  %values, %filled, %added, %count = sparse_tensor.expand %0
    : tensor<4x8xf64, #CSC> to memref<?xf64>, memref<?xi1>, memref<?xindex>
  return %added : memref<?xindex>
}

// CHECK-LABEL: func @sparse_expansion3(
//       CHECK: %[[C1:.*]] = arith.constant 1 : index
//       CHECK: %[[N:.*]] = call @newSparseTensor
//       CHECK: %[[S:.*]] = call @sparseDimSize(%[[N]], %c1) : (!llvm.ptr<i8>, index) -> index
//       CHECK: %[[A:.*]] = memref.alloc(%[[S]]) : memref<?xf64>
//       CHECK: %[[B:.*]] = memref.alloc(%[[S]]) : memref<?xi1>
//       CHECK: %[[C:.*]] = memref.alloc(%[[S]]) : memref<?xindex>
//   CHECK-DAG: linalg.fill ins(%{{.*}} : f64) outs(%[[A]] : memref<?xf64>)
//   CHECK-DAG: linalg.fill ins(%{{.*}} : i1) outs(%[[B]] : memref<?xi1>)
//       CHECK: return %[[C]] : memref<?xindex>
func.func @sparse_expansion3(%arg0: index, %arg1: index) -> memref<?xindex> {
  %0 = bufferization.alloc_tensor(%arg0, %arg1) : tensor<?x?xf64, #CSC>
  %values, %filled, %added, %count = sparse_tensor.expand %0
    : tensor<?x?xf64, #CSC> to memref<?xf64>, memref<?xi1>, memref<?xindex>
  return %added : memref<?xindex>
}

// CHECK-LABEL: func @sparse_compression(
//  CHECK-SAME: %[[A:.*0]]: !llvm.ptr<i8>,
//  CHECK-SAME: %[[B:.*1]]: memref<?xf64>,
//  CHECK-SAME: %[[C:.*2]]: memref<?xi1>,
//  CHECK-SAME: %[[D:.*3]]: memref<?xindex>,
//  CHECK-SAME: %[[E:.*4]]: index,
//  CHECK-SAME: %[[F:.*5]]: index)
//   CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
//   CHECK-DAG: %[[X:.*]] = memref.alloca() : memref<2xindex>
//   CHECK-DAG: %[[Y:.*]] = memref.cast %[[X]] : memref<2xindex> to memref<?xindex>
//       CHECK: memref.store %[[F]], %[[X]][%[[C0]]] : memref<2xindex>
//       CHECK: call @expInsertF64(%[[A]], %[[Y]], %[[B]], %[[C]], %[[D]], %[[E]])
//   CHECK-DAG: memref.dealloc %[[B]] : memref<?xf64>
//   CHECK-DAG: memref.dealloc %[[C]] : memref<?xi1>
//   CHECK-DAG: memref.dealloc %[[D]] : memref<?xindex>
//       CHECK: return
func.func @sparse_compression(%tensor: tensor<8x8xf64, #CSR>,
                              %values: memref<?xf64>,
                              %filled: memref<?xi1>,
                              %added: memref<?xindex>,
                              %count: index,
                              %i: index) {
  sparse_tensor.compress %values, %filled, %added, %count into %tensor[%i]
    : memref<?xf64>, memref<?xi1>, memref<?xindex>, tensor<8x8xf64, #CSR>
  return
}

// CHECK-LABEL: func @sparse_out1(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>,
//  CHECK-SAME: %[[B:.*]]: !llvm.ptr<i8>)
//  CHECK-DAG:  %[[ToCOO:.*]] = arith.constant 5 : i32
//  CHECK-DAG:  %[[Sort:.*]] = arith.constant false
//       CHECK: %[[COO:.*]] = call @newSparseTensor(%{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %[[ToCOO]], %[[A]])
//       CHECK: call @outSparseTensorF64(%[[COO]], %[[B]], %[[Sort]]) : (!llvm.ptr<i8>, !llvm.ptr<i8>, i1) -> ()
//       CHECK: call @delSparseTensorCOOF64(%[[COO]])
//       CHECK: return
func.func @sparse_out1(%arg0: tensor<?x?xf64, #CSR>, %arg1: !llvm.ptr<i8>) {
  sparse_tensor.out %arg0, %arg1 : tensor<?x?xf64, #CSR>, !llvm.ptr<i8>
  return
}

// CHECK-LABEL: func @sparse_out2(
//  CHECK-SAME: %[[A:.*]]: !llvm.ptr<i8>,
//  CHECK-SAME: %[[B:.*]]: !llvm.ptr<i8>)
//  CHECK-DAG:  %[[ToCOO:.*]] = arith.constant 5 : i32
//  CHECK-DAG:  %[[Sort:.*]] = arith.constant true
//       CHECK: %[[COO:.*]] = call @newSparseTensor(%{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %[[ToCOO]], %[[A]])
//       CHECK: call @outSparseTensorF32(%[[COO]], %[[B]], %[[Sort]]) : (!llvm.ptr<i8>, !llvm.ptr<i8>, i1) -> ()
//       CHECK: call @delSparseTensorCOOF32(%[[COO]])
//       CHECK: return
func.func @sparse_out2(%arg0: tensor<?x?x?xf32, #SparseTensor>, %arg1: !llvm.ptr<i8>) {
  sparse_tensor.out %arg0, %arg1 : tensor<?x?x?xf32, #SparseTensor>, !llvm.ptr<i8>
  return
}

// CHECK-LABEL: func @sparse_and_dense_init(
//       CHECK: %[[S:.*]] = call @newSparseTensor
//       CHECK: %[[D:.*]] = bufferization.alloc_tensor
//       CHECK: return %[[S]], %[[D]] : !llvm.ptr<i8>, tensor<?x?xf64>
func.func @sparse_and_dense_init(%arg0: index, %arg1: index)
           -> (tensor<?x?xf64, #CSR>, tensor<?x?xf64>) {
  %0 = bufferization.alloc_tensor(%arg0, %arg1) : tensor<?x?xf64, #CSR>
  %1 = sparse_tensor.load %0 : tensor<?x?xf64, #CSR>
  %2 = bufferization.alloc_tensor(%arg0, %arg1) : tensor<?x?xf64>
  return %1, %2 : tensor<?x?xf64, #CSR>, tensor<?x?xf64>
}
