.PHONY: csim cosim hw hls mktemp

APP ?= blur
SDA_VER ?= 2017.1
TILE_SIZE_DIM_0 ?= 2000
#TILE_SIZE_DIM1 ?= 1024
BURST_LENGTH ?= 100000
UNROLL_FACTOR ?= 16

CSIM_XCLBIN ?= $(APP)-csim-tile$(TILE_SIZE_DIM_0)-unroll$(UNROLL_FACTOR)-burst$(BURST_LENGTH).xclbin
COSIM_XCLBIN ?= $(APP)-cosim-tile$(TILE_SIZE_DIM_0)-unroll$(UNROLL_FACTOR)-burst$(BURST_LENGTH).xclbin
HW_XCLBIN ?= $(APP)-hw-tile$(TILE_SIZE_DIM_0)-unroll$(UNROLL_FACTOR)-burst$(BURST_LENGTH).xclbin

KERNEL_SRCS ?= $(APP)_kernel-tile$(TILE_SIZE_DIM_0)-unroll$(UNROLL_FACTOR).cpp
KERNEL_NAME ?= $(APP)_kernel
HOST_SRCS ?= $(APP)_run.cpp $(APP).cpp
HOST_ARGS ?= 2000 1000
HOST_BIN ?= $(APP)-tile$(TILE_SIZE_DIM_0)-burst$(BURST_LENGTH)

SRC ?= src
OBJ ?= obj
BIN ?= bin
BIT ?= bit
RPT ?= rpt

CXX ?= g++
CLCXX ?= xocc

XILINX_SDACCEL ?= /opt/tools/xilinx/SDx/$(SDA_VER)
WITH_SDACCEL = SDA_VER=$(SDA_VER) with-sdaccel

HOST_CFLAGS = -std=c++0x -g -Wall -DFPGA_DEVICE -DC_KERNEL -I$(XILINX_SDACCEL)/runtime/include/1_2
HOST_LFLAGS = -L$(XILINX_SDACCEL)/runtime/lib/x86_64 -lxilinxopencl -lrt -ldl -lpthread -lz $(shell libpng-config --ldflags)
#HOST_LFLAGS = -L$(XILINX_SDACCEL)/runtime/lib/x86_64 -lxilinxopencl -llmx6.0 -ldl -lpthread -lz $(shell libpng-config --ldflags)

XDEVICE = xilinx:adm-pcie-7v3:1ddr:3.0
HOST_CFLAGS += -DTARGET_DEVICE=\"$(XDEVICE)\"
HOST_CFLAGS += -DTILE_SIZE_DIM_0=$(TILE_SIZE_DIM_0) -DBURST_LENGTH=$(BURST_LENGTH) -DUNROLL_FACTOR=$(UNROLL_FACTOR)

CLCXX_OPT = $(CLCXX_OPT_LEVEL) $(DEVICE_REPO_OPT) --xdevice $(XDEVICE) $(KERNEL_DEFS) $(KERNEL_INCS)
CLCXX_OPT += --kernel $(KERNEL_NAME)
CLCXX_OPT += -s -g
CLCXX_OPT += -DTILE_SIZE_DIM_0=$(TILE_SIZE_DIM_0) -DBURST_LENGTH=$(BURST_LENGTH) -DUNROLL_FACTOR=$(UNROLL_FACTOR)
CLCXX_CSIM_OPT = -t sw_emu
CLCXX_COSIM_OPT = -t hw_emu
CLCXX_HW_OPT = -t hw

csim: $(BIN)/$(HOST_BIN) $(BIT)/$(CSIM_XCLBIN)
	ulimit -s 10000000;XCL_EMULATION_MODE=true $(WITH_SDACCEL) $^ $(HOST_ARGS)

cosim: $(BIN)/$(HOST_BIN) $(BIT)/$(COSIM_XCLBIN)
	XCL_EMULATION_MODE=true $(WITH_SDACCEL) $^ $(HOST_ARGS)

hw: $(BIN)/$(HOST_BIN) $(BIT)/$(HW_XCLBIN)
	$(WITH_SDACCEL) $^ $(HOST_ARGS)

hls: $(OBJ)/$(HW_XCLBIN:.xclbin=.xo)

mktemp:
	@TMP=$$(mktemp -d --suffix=-sdaccel-2016.3-halide1-tmp);mkdir $${TMP}/src;cp -r $(SRC)/* $${TMP}/src;cp makefile $${TMP};echo -e "#!$${SHELL}\nrm \$$0;cd $${TMP}\n$${SHELL} \$$@ && rm -r $${TMP}" > mktemp.sh;chmod +x mktemp.sh

$(SRC)/$(KERNEL_SRCS): $(SRC)/$(APP).json
	./generate-kernel.py < $^ > $@

$(BIN)/$(HOST_BIN): $(HOST_SRCS:%.cpp=$(OBJ)/%-tile$(TILE_SIZE_DIM_0).o)
	@mkdir -p $(BIN)
	$(WITH_SDACCEL) $(CXX) $(HOST_LFLAGS) $^ -o $@

$(OBJ)/%-tile$(TILE_SIZE_DIM_0).o: $(SRC)/%.cpp $(SRC)/$(APP)_params.h
	@mkdir -p $(OBJ)
	$(WITH_SDACCEL) $(CXX) $(HOST_CFLAGS) -MM -MP -MT $@ -MF $(@:.o=.d) $<
	$(WITH_SDACCEL) $(CXX) $(HOST_CFLAGS) -c $< -o $@

-include $(OBJ)/$(HOST_SRCS:%.cpp=%.d)

$(BIT)/$(CSIM_XCLBIN): $(SRC)/$(KERNEL_SRCS) $(BIN)/emconfig.json $(SRC)/$(APP)_params.h
	@mkdir -p $(BIT)
	$(WITH_SDACCEL) $(CLCXX) $(CLCXX_CSIM_OPT) $(CLCXX_OPT) -o $@ $<
	@rm -rf $$(ls -d .Xil/* 2>/dev/null|grep -vE "\-($$(pgrep xocc|tr '\n' '|'))-")
	@rmdir .Xil --ignore-fail-on-non-empty 2>/dev/null; exit 0

$(BIT)/$(COSIM_XCLBIN): $(SRC)/$(KERNEL_SRCS) $(BIN)/emconfig.json $(SRC)/$(APP)_params.h
	@mkdir -p $(BIT)
	@mkdir -p $(RPT)
	$(WITH_SDACCEL) $(CLCXX) $(CLCXX_COSIM_OPT) $(CLCXX_OPT) -o $@ $<
	@rm -rf $$(ls -d .Xil/* 2>/dev/null|grep -vE "\-($$(pgrep xocc|tr '\n' '|'))-")
	@rmdir .Xil --ignore-fail-on-non-empty 2>/dev/null; exit 0

$(BIT)/$(HW_XCLBIN): $(OBJ)/$(HW_XCLBIN:.xclbin=.xo)
	@mkdir -p $(BIT)
	$(WITH_SDACCEL) $(CLCXX) $(CLCXX_HW_OPT) $(CLCXX_OPT) -l -o $@ $<
	@rm -rf $$(ls -d .Xil/* 2>/dev/null|grep -vE "\-($$(pgrep xocc|tr '\n' '|'))-")
	@rmdir .Xil --ignore-fail-on-non-empty 2>/dev/null; exit 0

$(OBJ)/$(HW_XCLBIN:.xclbin=.xo): $(SRC)/$(KERNEL_SRCS) $(SRC)/$(APP)_params.h
	@mkdir -p $(OBJ)
	@mkdir -p $(RPT)/$(HW_XCLBIN:.xclbin=)
	$(WITH_SDACCEL) $(CLCXX) $(CLCXX_HW_OPT) $(CLCXX_OPT) -c -o $@ $<
	@cp _xocc_compile_$(KERNEL_SRCS:%.cpp=%)_$(HW_XCLBIN:%.xclbin=%.dir)/impl/kernels/$(KERNEL_NAME)/$(KERNEL_NAME)/solution_OCL_REGION_0/syn/report/*.rpt $(RPT)/$(HW_XCLBIN:.xclbin=)
	@rm -rf $$(ls -d .Xil/* 2>/dev/null|grep -vE "\-($$(pgrep xocc|tr '\n' '|'))-")
	@rmdir .Xil --ignore-fail-on-non-empty 2>/dev/null; exit 0

$(BIN)/emconfig.json:
	@mkdir -p $(BIN)
	cd $(BIN);$(WITH_SDACCEL) emconfigutil --xdevice $(XDEVICE) $(DEVICE_REPO_OPT) --od .

