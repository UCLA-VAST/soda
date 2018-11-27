#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include<time.h>

#include"seidel2d.h"

int seidel2d_test(const char*, const int dims[4]);
int main(int argc, char **argv)
{
    if(argc != 4)
    {
        fprintf(stderr, "Usage: \n    %s <xclbin> <input width> <input height>\n", argv[0]);
        return 1;
    }
    int dims[4] = {atoi(argv[2]), atoi(argv[3]), 0, 0};
    return seidel2d_test(argv[1], dims);
}