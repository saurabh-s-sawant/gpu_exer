#include <cmath>
#include <iomanip>
#include <math.h>
#include <iostream>
#include <assert.h>
/** Compile with one of three options for matrix multiplication:
  * NAIVE, CONSTMEM, TILED_CONSTMEM_TYPE_1, TILED_CONSTMEM_TYPE_2, TILED_CONSTMEM_CACHEHALO
  * For Printing use flag: PRINT
  **/

#define STENCIL_RADIUS 1

#ifdef NAIVE
const int BLOCK_SIZE = 32;
#elif REGISTERTILING_THREADCOARSENING
const int IN_TILE_SIZE = 32;
const int OUT_TILE_SIZE = IN_TILE_SIZE - 2*STENCIL_RADIUS;
#endif

#ifdef NAIVE
__global__ void stencil_naive(float *out, const float *in, unsigned int N) 
{
    /* N  : domain size (N x N x N)
       in : linearized array of input data
       out: linearized array of output data
       */
   unsigned int k = blockDim.z*blockIdx.z + threadIdx.z;
   unsigned int j = blockDim.y*blockIdx.y + threadIdx.y;
   unsigned int i = blockDim.x*blockIdx.x + threadIdx.x;

   if( k >=1 && k < N-1 &&
       j >=1 && j < N-1 &&
       i >=1 && i < N-1 ) 
   {
       out[k*N*N + j*N + i] = c0*in[k*N*N     + J*N      + i]
                            + c1*in[(k-1)*N*N + J*N      + i]
                            + c2*in[(k+1)*N*N + J*N      + i]	     
                            + c3*in[k*N*N     + (J-1)*N  + i]
                            + c4*in[k*N*N     + (J+1)*N  + i]	     
                            + c5*in[k*N*N     + J*N      + (i-1)]
                            + c6*in[k*N*N     + J*N      + (i+1)];	    
   }

}
#endif

#ifdef TILED
__global__ void stencil_tiled(float *out, const float *in, unsigned int N) 
{
   int k = OUT_TILE_SIZE*blockIdx.z + threadIdx.z - 1;
   int j = OUT_TILE_SIZE*blockIdx.y + threadIdx.y - 1;
   int i = OUT_TILE_SIZE*blockIdx.x + threadIdx.x - 1;

   __shared__ float in_s[IN_TILE_SIZE][IN_TILE_SIZE][IN_TILE_SIZE];

   if(k >=0 && k< N && j >=0 && j < N && i >=0 && i < N) 
   {
       in_s[threadIdx.z][threadIdx.y][threadIdx.x] = in[k*NN + j*N + i];
   }
   /*Here dont have to do else 0 as in convolution because of the limits*/
   __syncthreads();

   if( k >=1 && k < N-1 &&
       j >=1 && j < N-1 &&
       i >=1 && i < N-1 ) 
   {
       if(threadIdx.z >=1 && threadIdx.z < (IN_TILE_DIM - 1) &&
	  threadIdx.y >=1 && threadIdx.y < (IN_TILE_DIM - 1) &&	       
	  threadIdx.x >=1 && threadIdx.x < (IN_TILE_DIM -1)) /*NOTE THIS*/
       {
           out[k*N*N + j*N + i] = c0*in_s[threadIdx.z][threadIdx.y][threadIdx.x]
                                + c1*in_s[threadIdx.z-1][threadIdx.y][threadIdx.x]
                                + c2*in_s[threadIdx.z+1][threadIdx.y][threadIdx.x]  
                                + c3*in_s[threadIdx.z][threadIdx.y-1][threadIdx.x]
                                + c4*in_s[threadIdx.z][threadIdx.y+1][threadIdx.x]  
                                + c5*in_s[threadIdx.z][threadIdx.y][threadIdx.x-1]
                                + c6*in_s[threadIdx.z][threadIdx.y][threadIdx.x+1];	    
       }
   }

}
#endif

#ifdef THREADCOARSENING
__global__ void stencil_threadcoarsening(float *out, const float *in, unsigned int N) 
{
   unsigned int kstart = OUT_TILE_SIZE*blockIdx.z; /*NOTE THIS*/
   unsigned int j = OUT_TILE_SIZE*blockIdx.y + threadIdx.y - 1;
   unsigned int i = OUT_TILE_SIZE*blockIdx.x + threadIdx.x - 1;
   
   __shared__ float in_prev_s[IN_TILE_DIM][IN_TILE_DIM];
   __shared__ float in_curr_s[IN_TILE_DIM][IN_TILE_DIM];
   __shared__ float in_next_s[IN_TILE_DIM][IN_TILE_DIM];

   /*NOTE THIS*/
   if(kstart-1 >=0 && kstart-1 < N && j >= 0 && j < N && i >=0 && i < N) 
   {
       in_prev_s[threadIdx.y][threadIdx.x] = in[(kstart-1)*NN + j*N + i];
   }
   /*NOTE THIS*/
   if(kstart >=0 && kstart < N && j >= 0 && j < N && i >=0 && i < N) 
   {
       in_curr_s[threadIdx.y][threadIdx.x] = in[kstart*NN + j*N + i];
   }


   for(int k = kstart; k < (kshart + OUT_TILE_SIZE); ++k)  /*NOTE THIS LIMIT OF FOR LOOP*/
   {

       if(k+1 >=0 && k+1 < N && j >= 0 && j < N && i >=0 && i < N) 
       {
           in_next_s[threadIdx.y][threadIdx.x] = in[(k+1)*NN + j*N + i];
       }
       __syncthreads();


       if( k >=1 && k < N-1 &&
           j >=1 && j < N-1 &&
           i >=1 && i < N-1 ) 
       {
           if(threadIdx.y >=1 && threadIdx.y < (IN_TILE_DIM - 1) &&	       
              threadIdx.x >=1 && threadIdx.x < (IN_TILE_DIM -1))  /*NOTE THIS*/
           {
               out[k*N*N + j*N + i] = c0*in_curr_s[threadIdx.y][threadIdx.x]
                                    + c1*in_prev_s[threadIdx.y][threadIdx.x]
                                    + c2*in_next_s[threadIdx.y][threadIdx.x]  
                                    + c3*in_curr_s[threadIdx.y-1][threadIdx.x]
                                    + c4*in_curr_s[threadIdx.y+1][threadIdx.x]  
                                    + c5*in_curr_s[threadIdx.y][threadIdx.x-1]
                                    + c6*in_curr_s[threadIdx.y][threadIdx.x+1];	    
	   }
       }

       __syncthreads();
       in_prev_s[threadIdx.y][threadIdx.x] = in_curr_s[threadIdx.y][threadIdx.x];
       in_curr_s[threadIdx.y][threadIdx.x] = in_next_s[threadIdx.y][threadIdx.x];
   }

}
#endif

#ifdef REGISTERTILING_THREADCOARSENING
__global__ void stencil_registertiling_threadcoarsening(float *out, const float *in, unsigned int N) 
{
   unsigned int kstart = OUT_TILE_SIZE*blockIdx.z; 
   unsigned int j = OUT_TILE_SIZE*blockIdx.y + threadIdx.y - 1;
   unsigned int i = OUT_TILE_SIZE*blockIdx.x + threadIdx.x - 1;
 
   float in_prev;  
   __shared__ float in_curr_s[IN_TILE_DIM][IN_TILE_DIM];
   float in_curr;  
   float in_next;


   /*If condition remains the same*/
   if(kstart-1 >=0 && kstart-1 < N && j >= 0 && j < N && i >=0 && i < N) 
   {
       in_prev = in[(kstart-1)*NN + j*N + i];
   }

   /*This remains the same*/
   if(kstart >=0 && kstart < N && j >= 0 && j < N && i >=0 && i < N) 
   {
       in_curr = in[kstart*NN + j*N + i];
       in_curr_s[threadIdx.y][threadIdx.x] = in_curr;

   }

   for(int k = kstart; k < (kshart + OUT_TILE_SIZE); ++k)  /*NOTE THIS LIMIT OF FOR LOOP*/
   {

       /*If condition remains the same*/
       if(k+1 >=0 && k+1 < N && j >= 0 && j < N && i >=0 && i < N) 
       {
           in_next = in[(k+1)*NN + j*N + i];
       }

       __syncthreads(); /*I this this can be at the end of the loop if we add __syncthreads before the forloop begins*/

       if( k >=1 && k < N-1 &&
           j >=1 && j < N-1 &&
           i >=1 && i < N-1 ) 
       {
           if(threadIdx.y >=1 && threadIdx.y < (IN_TILE_DIM - 1) &&	       
              threadIdx.x >=1 && threadIdx.x < (IN_TILE_DIM -1))  /*NOTE THIS*/
           {
               out[k*N*N + j*N + i] = c0*in_curr
                                    + c1*in_prev
                                    + c2*in_next
                                    + c3*in_curr_s[threadIdx.y-1][threadIdx.x]
                                    + c4*in_curr_s[threadIdx.y+1][threadIdx.x]  
                                    + c5*in_curr_s[threadIdx.y][threadIdx.x-1]
                                    + c6*in_curr_s[threadIdx.y][threadIdx.x+1];	    
	   }
       }

       __syncthreads();

       in_prev = in_curr;
       in_curr = in_next;
       in_curr_s[threadIdx.y][threadIdx.x] = in_curr;
   }
}
#endif



void set_zero(float *M) 
{
    if(M != NULL) 
    {	
        int size = sizeof(M)/sizeof(M[0]);

	std::cout << "setting array of size: " << size << " to zero\n";
        for (int i = 0; i < size; ++i) 
        {
            M[i] = 0;    
        }
    }
}


void print_matrix(const float *M, int COL, int ROW) 
{
    for (int row = 0; row < ROW; ++row) 
    {
        for (int col = 0; col < COL; ++col) 
	{
            std::cout << std::setw(5) << M[row*COL + col];
	}
        std::cout << "\n";
    }
    std::cout << "\n";
}


void check_error(const float* h_output, const float* answer_check, const int size) {

    bool test_passed = true;
    for(int n=0; n<size; ++n) {	
        if(h_output[n] != answer_check[n]) {
           std::cout << "error: n, output, correct_ans:" << std::setw(10) << n << std::setw(10) << h_output[n] << std::setw(10) << answer_check[n] << "\n";
	   test_passed = false;
           break; 	    
        }
    }
    if(test_passed) std::cout << "Matrix Convolution Test Passed! \n";
}

int main (int argc, char* argv[])
{ 
    /*define dimensions*/ 
    /*A (Height x InnerSize)  x B (InnerSize x Width)  = M (Height x Width) **/
    const int N = 512;
    const int FilterSize = 2*FILTER_RADIUS+1;

    const int matA_memsize = Height*Width*sizeof(float);
    const int matM_memsize = Height*Width*sizeof(float);
    const int matF_memsize = FilterSize*FilterSize*sizeof(float);

#ifdef NAIVE 
    dim3 dimGrid(ceil(N/static_cast<float>(BLOCK_SIZE)), 
		 ceil(N/static_cast<float>(BLOCK_SIZE), 
		 ceil(N/static_cast<float>(BLOCK_SIZE)));

    dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE);
    std::cout << "cubic BLOCK_SIZE: " << std::setw(10) << BLOCK_SIZE  << "\n";

#elif REGISTERTILING_THREADCOARSENING
    dim3 dimGrid(ceil(N/static_cast<float>(OUT_TILE_SIZE)), 
	         ceil(N/static_cast<float>(OUT_TILE_SIZE)), 
		 ceil(N/static_cast<float>(OUT_TILE_SIZE));

    dim3 dimBlock(IN_TILE_SIZE, IN_TILE_SIZE, IN_TILE_SIZE);
    std::cout << "IN_TILE_SIZE, OUT_TILE_SIZE (square): " << std::setw(10) << IN_TILE_SIZE  << std::setw(10) << OUT_TILE_SIZE << "\n";
#endif

    int devID=0;
    if(argc > 1) devID = atoi(argv[1]);

    /*print cuda device properties*/
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, devID);
    std::cout << "\nDevice: " << prop.name << "\n";
    std::cout << "Matrix sizes (height, width, filter size): "    << std::setw(10) << Height << std::setw(10) << Width << std::setw(10) << FilterSize << "\n";
    std::cout << "dimGrid (x,y,z):  "<< std::setw(10) << dimGrid.x  << std::setw(10) << dimGrid.y << std::setw(10) << dimGrid.z << "\n";
    std::cout << "dimBlock (x,y,z): "<< std::setw(10) << dimBlock.x << std::setw(10) << dimBlock.y << std::setw(10) << dimBlock.z << "\n";

    std::cout << "\nconstant memory (KB): " << prop.totalConstMem/1024 << "\n";
    std::cout << "total global memory (GB): " << prop.totalGlobalMem/(pow(1024,3)) << "\n";
    std::cout << "shared memory per block (KB): " << prop.sharedMemPerBlock/1024 << "\n";
    std::cout << "shared memory per multiprocessor (KB): " << prop.sharedMemPerMultiprocessor/1024 << "\n";
    std::cout << "register per block: " << prop.regsPerBlock << "\n";
    std::cout << "register per multiprocessor: " << prop.regsPerMultiprocessor << "\n";
    std::cout << "multiProcessorCount: " << prop.multiProcessorCount << "\n";
    std::cout << "warpSize: " << prop.warpSize<< "\n";
    /*cudaSetDevice(devID)*/

    /*define arrays on host and device*/
    /*A*B = M*/
    float* h_A = (float *) malloc(matA_memsize);
    float* h_F = (float *) malloc(matF_memsize);
    float* h_M = (float *) malloc(matM_memsize);

    float* M_check = (float *) malloc(matM_memsize);

    float* d_A = NULL;
    cudaMalloc(&d_A, matA_memsize);
    float* d_F = NULL;
    cudaMalloc(&d_F, matF_memsize);
    float* d_M = NULL;
    cudaMalloc(&d_M, matM_memsize);

    /*initializing input array*/
    for (int j=0; j < Height; ++j) {
	for (int i=0; i < Width; ++i) {
	    h_A [j*Width + i] = static_cast<float>(j);
	}
    }
    for (int j=0; j < FilterSize; ++j) {
	for (int i=0; i < FilterSize; ++i) {
	    h_F [j*FilterSize + i] = static_cast<float>((j));
	}
    }
    /*correct answer for error checking*/
    for (int row=0; row < Height; ++row) 
    {
	for (int col=0; col < Width; ++col) 
	{
	    float sum = 0.f;
            for(int j =  0; j < FilterSize; ++j) 
	    {
                for(int i = 0; i < FilterSize; ++i) 
	        {
	            int inCol = col + i - FILTER_RADIUS; 		    
	            int inRow = row + j - FILTER_RADIUS;
	            if(inRow >= 0 && inRow < Height && inCol >=0 && inCol < Width) 
	            {
                        sum += h_A[inRow*Width + inCol] * h_F[j*FilterSize + i];     
	            }
	        }
	    }
	    M_check [row*Width + col] = sum;
	}
    }

#ifdef PRINT
    std::cout << "\nWriting A matrix:\n";
    print_matrix(h_A, Width, Height);

    std::cout << "Writing Filter F:\n";
    print_matrix(h_F, FilterSize, FilterSize);

    std::cout << "Writing correct answer for M matrix:\n";
    print_matrix(M_check, Width, Height);
#endif

    cudaMemcpy(d_A, h_A, matA_memsize, cudaMemcpyHostToDevice);

#ifdef NAIVE
    cudaMemcpy(d_F, h_F, matF_memsize, cudaMemcpyHostToDevice);
#else  //use constant memory
    cudaMemcpyToSymbol(F, h_F, matF_memsize);
#endif

    cudaMemset(d_M, 0, matM_memsize);
    cudaEvent_t startEvent, stopEvent;
    cudaEventCreate(&startEvent);
    cudaEventCreate(&stopEvent);
    float ms;
    cudaEventRecord(startEvent, 0);

#ifdef NAIVE
    stencil_naive<<<dimGrid, dimBlock>>>(d_out, d_in, N);
#elif REGISTERTILING_THREADCOARSENING
    stencil_registertiling_threadcoarsening<<<dimGrid, dimBlock>>>(d_out, d_in, N);
#endif

    cudaEventRecord(stopEvent, 0);
    cudaEventSynchronize(stopEvent);
    cudaEventElapsedTime(&ms, startEvent, stopEvent);
    std::cout << "\nElapsed time to run kernel (ms): " << ms << "\n";

    cudaMemcpy(h_M, d_M, matM_memsize, cudaMemcpyDeviceToHost); 
  
#ifdef PRINT
    std::cout << "Writing M matrix:\n";
    print_matrix(h_M, Width, Height);
#endif

   check_error(h_M, M_check, Width*Height);

//error_exit:
    /*free memory*/
    cudaEventDestroy(startEvent);
    cudaEventDestroy(stopEvent);

    free(h_A);
    free(h_F);
    free(h_M);
    free(M_check);

    cudaFree(d_A);
    cudaFree(d_F);
    cudaFree(d_M);

    cudaDeviceReset();
    return 0;
}

