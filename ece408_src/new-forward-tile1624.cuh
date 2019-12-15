#ifndef MXNET_OPERATOR_NEW_FORWARD_CUH_
#define MXNET_OPERATOR_NEW_FORWARD_CUH_

#define TILE_WIDTH_1 16
#define TILE_WIDTH_2 24


#include <mxnet/base.h>

namespace mxnet
{
namespace op
{

__global__ void conv_layer_kernel1(int H, int W, int M, int C, int K, int W_out, int H_out, float* __restrict__ x, float* __restrict__ k, float* __restrict__ y){

#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]

    __shared__ float tileMatA[TILE_WIDTH_1][TILE_WIDTH_1];
    __shared__ float tileMatB[TILE_WIDTH_1][TILE_WIDTH_1];

    int b = blockIdx.z;
    int tx = threadIdx.x; 
    int ty = threadIdx.y;
    int row = blockIdx.y * TILE_WIDTH_1 + ty;
    int column = blockIdx.x * TILE_WIDTH_1 + tx;
    int numMatAColumns = C*K*K;

    float acc = 0.0;

    int num_iterations = ceil(numMatAColumns/(1.0*TILE_WIDTH_1));

    #pragma unroll
    for (int i = 0; i < num_iterations; i++) {
        int temp_col = i*TILE_WIDTH_1 + tx;
        int temp_row = i*TILE_WIDTH_1 + ty;

        tileMatA[ty][tx] = 0;
        tileMatB[ty][tx] = 0;

        int W_m = row;
        int W_c = temp_col/(K*K);
        int W_h = (temp_col%(K*K))/K;
        int W_w = (temp_col%(K*K))%K;
        if (temp_col < numMatAColumns && row < M)
            tileMatA[ty][tx] = k4d(W_m, W_c, W_h, W_w);
        else
            tileMatA[ty][tx] = 0;

        int X_b = b;
        int X_c = temp_row/(K*K);
        int X_p = temp_row%(K*K)/K, X_q = (temp_row%(K*K))%K; 
        int X_h = column/W_out, X_w = column%W_out;
        if (temp_row < numMatAColumns && column < H_out*W_out)
            tileMatB[ty][tx] = x4d(X_b, X_c, X_h + X_p, X_w + X_q);
        else
            tileMatB[ty][tx] = 0;

        __syncthreads();
        for (int q = 0; q < TILE_WIDTH_1; q++)
            acc += tileMatA[ty][q] * tileMatB[q][tx];
        __syncthreads();
    }

        int Y_b = b;
        int Y_m = row;
        int Y_h = column / W_out, Y_w = column % W_out;
    
        if (row < M && column < W_out*H_out)
            y4d(Y_b, Y_m, Y_h, Y_w) = acc;
}

__global__ void conv_layer_kernel2(int H, int W, int M, int C, int K, int W_out, int H_out, float* __restrict__ x, float* __restrict__ k, float* __restrict__ y){

#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]

    __shared__ float tileMatA[TILE_WIDTH_2][TILE_WIDTH_2];
    __shared__ float tileMatB[TILE_WIDTH_2][TILE_WIDTH_2];

    int b = blockIdx.z;
    int tx = threadIdx.x; 
    int ty = threadIdx.y;
    int row = blockIdx.y * TILE_WIDTH_2 + ty;
    int column = blockIdx.x * TILE_WIDTH_2 + tx;
    int numMatAColumns = C*K*K;

    float acc = 0.0;

    int num_iterations = ceil(numMatAColumns/(1.0*TILE_WIDTH_2));

    #pragma unroll
    for (int i = 0; i < num_iterations; i++) {
        int temp_col = i*TILE_WIDTH_2 + tx;
        int temp_row = i*TILE_WIDTH_2 + ty;

        tileMatA[ty][tx] = 0;
        tileMatB[ty][tx] = 0;

        int W_m = row;
        int W_c = temp_col/(K*K);
        int W_h = (temp_col%(K*K))/K;
        int W_w = (temp_col%(K*K))%K;
        if (temp_col < numMatAColumns && row < M)
            tileMatA[ty][tx] = k4d(W_m, W_c, W_h, W_w);
        else
            tileMatA[ty][tx] = 0;

        int X_b = b;
        int X_c = temp_row/(K*K);
        int X_p = temp_row%(K*K)/K, X_q = (temp_row%(K*K))%K; 
        int X_h = column/W_out, X_w = column%W_out;
        if (temp_row < numMatAColumns && column < H_out*W_out)
            tileMatB[ty][tx] = x4d(X_b, X_c, X_h + X_p, X_w + X_q);
        else
            tileMatB[ty][tx] = 0;

        __syncthreads();
        for (int q = 0; q < TILE_WIDTH_2; q++)
            acc += tileMatA[ty][q] * tileMatB[q][tx];
        __syncthreads();
    }

        int Y_b = b;
        int Y_m = row;
        int Y_h = column / W_out, Y_w = column % W_out;
    
        if (row < M && column < W_out*H_out)
            y4d(Y_b, Y_m, Y_h, Y_w) = acc;
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
    //const int W_grid = ceil((1.0*W_out) / TILE_WIDTH);
    //const int H_grid = ceil((1.0*H_out) / TILE_WIDTH);
    //const int Z = H_grid * W_grid;

    //Unroll matrix
    //int W_unroll = C * K * K;
    //int H_unroll = H_out * W_out;

    //int num_threads_unroll = C * H_out * W_out;
    //int num_blocks_unroll = ceil(float(1.0*num_threads_unroll)/MAX_THREADS);

    //float *x_unroll_host; //Unrolled x matrix
    //float *x_unroll_device;
    //cudaMalloc((void**) &x_unroll_device, W_unroll * H_unroll * sizeof(float));

	//int numARows = M;
	//int numACols = C*K*K;
	//int numBRows = C*K*K;
	//int numBCols = H_out*W_out;
	//int numCRows = M;
	//int numCCols = H_out*W_out;
	//float* Y_ptr = y.dptr_;
	//float* X_ptr = x.dptr_;
    //float* W_ptr = w.dptr_;

    //printf("numARows is %d\n", numARows);
    //printf("numACols is %d\n", numACols);
    //printf("K is %d\n", K);

    //cudaMemcpyToSymbol(kernel, w.dptr_, sizeof(float)*numARows*numACols); //Store kernel in constant memory
    if (M > 20){

    dim3 gridDim(ceil((1.0*H_out*W_out)/TILE_WIDTH_2), ceil(M/(1.0*TILE_WIDTH_2)), B);
    dim3 blockDim(TILE_WIDTH_2, TILE_WIDTH_2, 1);
	conv_layer_kernel2<<<gridDim, blockDim>>>(H, W, M, C, K, W_out, H_out, x.dptr_, w.dptr_, y.dptr_);
	MSHADOW_CUDA_CALL(cudaDeviceSynchronize());
    }

    else{
    dim3 gridDim(ceil((1.0*H_out*W_out)/TILE_WIDTH_1), ceil(M/(1.0*TILE_WIDTH_1)), B);
    dim3 blockDim(TILE_WIDTH_1, TILE_WIDTH_1, 1);
    conv_layer_kernel1<<<gridDim, blockDim>>>(H, W, M, C, K, W_out, H_out, x.dptr_, w.dptr_, y.dptr_);
    
    
    MSHADOW_CUDA_CALL(cudaDeviceSynchronize());}

    

	//printf("unroll:%f\n", w.dptr_[0]);

    //Initialize block and grid dimensions for matrix mul


    

    //dim3 gridDim(B, M, Z);
    //dim3 blockDim(TILE_WIDTH, TILE_WIDTH, 1);

    // Call the kernel
    //forward_kernel<<<gridDim, blockDim>>>(y.dptr_,x.dptr_,w.dptr_, B,M,C,H,W,K);

    // Use MSHADOW_CUDA_CALL to check for CUDA runtime errors.
    //MSHADOW_CUDA_CALL(cudaDeviceSynchronize());

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
