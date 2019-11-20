
#ifndef MXNET_OPERATOR_NEW_FORWARD_CUH_
#define MXNET_OPERATOR_NEW_FORWARD_CUH_

#define TILE_WIDTH 16

#include <mxnet/base.h>

namespace mxnet
{
namespace op
{

__global__ void forward_kernel(float *y, const float *x, const float *k, const int B, const int M, const int C, const int H, const int W, const int K)
{

    /*
    Modify this function to implement the forward pass described in Chapter 16.
    We have added an additional dimension to the tensors to support an entire mini-batch
    The goal here is to be correct AND fast.
    We have some nice #defs for you below to simplify indexing. Feel free to use them, or create your own.
    */

    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    const int W_grid = ceil((1.0*W_out) / TILE_WIDTH);
    const int H_grid = ceil((1.0*H_out) / TILE_WIDTH);


#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]

    int b, m, h, w, c, p, q;
    b = blockIdx.x;
    m = blockIdx.y;
    h = blockIdx.z / W_grid * TILE_WIDTH + threadIdx.y;
    w = blockIdx.z % W_grid * TILE_WIDTH + threadIdx.x;
    if (h >= H_out || w >= W_out) return; //boundary checking

    float acc = 0.;
    for (c = 0; c < C; c++){ //sum over all input channels
        for (p = 0; p < K; p++){ //loop over K*K filter
            for (q = 0; q < K; q++){
                acc += x4d(b, c, h + p, w + q)*k4d(m, c, p, q);
            }
        }
    }
    y4d(b, m, h, w) = acc; 

#undef y4d
#undef x4d
#undef k4d
}

__global__ void unroll_kernel(float* x, float* x_unroll, int C, int H, int W, int K) {
/*
   Code to unroll input matrix to recast convolution layer as matrix multiply
*/

    #define x3d(i2, i1, i0) x[(i2) * (H * W) + (i1) * (W) + i0]
    #define x_unroll2d(i1, i0) x_unroll[(i1) * (W) + i0]

    int c, s, h_out, w_out, h_unroll, w_base, p, q;
    int b = blockIdx.x;
    int t = blockIdx.x*blockDim.x + threadIdx.x;
    int H_out = H - K + 1;
    int W_out = W - K + 1;
    int W_unroll = H_out * W_out;

    if (t < C * W_unroll) {

        c = t / W_unroll;
        s = t % W_unroll;
        h_out = s / W_out;
        w_out = s % W_out;
        h_unroll = h_out * W_out + w_out;
        w_base = c * K * K;
        for(p = 0; p < K; p++){
            for(q=0; q<K; q++){
                w_unroll = w_base + p * K + q;
                x_unroll2d(h_unroll, w_unroll) = x3d(c, h_out + p, w_out + q); //Need to compute proper indices for this line!!
            }

        }
    }
}

__global__ void foward_matmul_kernel(float* A, float* B, float* C, int numARows, int numAColumns, int numBRows, int numBColumns,
                                     int numCRows, int numCColumns){
/* Forward pass using matrix multiplication

*/

    __shared__ float subTileA[TILE_WIDTH][TILE_WIDTH];
	__shared__ float subTIleB[TILE_WIDTH][TILE_WIDTH];

	int bx = blockIdx.x;
	int by = blockIdx.y;
	int tx = threadIdx.x;
	int ty = threadIdx.y;

	int Row = by * TILE_WIDTH + ty;
  	int Col = bx * TILE_WIDTH + tx;

  	float Pvalue = 0;

  // Loop over the M and N tiles required to compute the P element
  // The code assumes that the Width is a multiple of TILE_WIDTH!
    for (int m = 0; m < (numAColumns-1)/TILE_WIDTH + 1; ++m) {
		// Collaborative loading of M and N tiles into shared memory
		if(Row < numARows && m*TILE_WIDTH+tx < numAColumns) {
		  subTileA[ty][tx] = A[Row*numAColumns + m*TILE_WIDTH+tx];
		}
		else {
		  subTileA[ty][tx] = 0;
		}
		if (m*TILE_WIDTH+ty < numBRows && Col < numBColumns) {
		  subTileB[ty][tx] = B[(m*TILE_WIDTH+ty)*numBColumns+Col];
		}
		else {
		  subTileB[ty][tx] = 0;
		}
		__syncthreads();
		if (Row < numCRows && Col < numCColumns) {
		  for (int k = 0; k < TILE_WIDTH; ++k) {
			Pvalue += subTileA[ty][k] * subTileB[k][tx];
		  }
		}
		__syncthreads();
    }
    if (Row < numCRows && Col < numCColumns) {
		C[Row*numCColumns+Col] = Pvalue;
    }
}


/* 
   This function is called by new-inl.h
   Any code you write should be executed by this function.
   For ECE408, we only expect the float version of the operator to be called, so here we specialize with only floats.
*/
template <>
void forward<gpu, float>(mshadow::Tensor<gpu, 4, float> &y, const mshadow::Tensor<gpu, 4, float> &x, const mshadow::Tensor<gpu, 4, float> &w)
{

    // Use mxnet's CHECK_EQ to do assertions.
    // Remove this assertion when you do your implementation!

    // Extract the tensor dimensions into B,M,C,H,W,K
    // ...
    const int B = x.shape_[0];
    const int M = y.shape_[1];
    const int C = x.shape_[1];
    const int H = x.shape_[2];
    const int W = x.shape_[3];
    const int K = w.shape_[3];
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    // Set the kernel dimensions
    const int W_grid = ceil((1.0*W_out) / TILE_WIDTH);
    const int H_grid = ceil((1.0*H_out) / TILE_WIDTH);
    const int Z = H_grid * W_grid;

    //Unroll matrix
    int W_unroll = C * K * K;
    int H_unroll = H_out * W_out;

    int num_threads_unroll = C * H_out * W_out;
    int num_blocks_unroll = ceil(float(num_threads_unroll)/TILE_WIDTH);

    float *x_unroll_host; //Unrolled x matrix
    float *x_unroll_device;
    cudaMalloc((void**) &x_unroll, W_unroll * H_unroll * sizeof(float));
    cudaMemcpy(x_unroll_device, x_unroll_host, W_unroll * H_unroll * sizeof(float), cudaMemcpyHostToDevice);
    unroll_kernel<<<num_blocks_unroll, TILE_WIDTH>>>(x, x_unroll, C, H, W, K);

    //dim3 gridDim(B, M, Z);
    //dim3 blockDim(TILE_WIDTH, TILE_WIDTH, 1);

    // Call the kernel
    //forward_kernel<<<gridDim, blockDim>>>(y.dptr_,x.dptr_,w.dptr_, B,M,C,H,W,K);

    // Use MSHADOW_CUDA_CALL to check for CUDA runtime errors.
    MSHADOW_CUDA_CALL(cudaDeviceSynchronize());

}

/* 
    This tells mxnet how to do an op when it's not a float.
    This is not used in the ECE408 project
*/
template <typename gpu, typename DType>
void forward(mshadow::Tensor<gpu, 4, DType> &y, const mshadow::Tensor<gpu, 4, DType> &x, const mshadow::Tensor<gpu, 4, DType> &w)
{
    CHECK_EQ(0,1) << "Remove this line and replace it with your implementation.";
}
}
}

#endif
