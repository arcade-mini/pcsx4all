TARGET = pcsx4all
PORT   = sdl
#A320   = 1
#GCW0   = 1
RS97   = 1

# Using 'gpulib' adapted from PCSX Rearmed is default, specify
# USE_GPULIB=0 as param to 'make' when building to disable it.
USE_GPULIB ?= 1

#GPU = gpu_dfxvideo
#GPU = gpu_drhell
#GPU = gpu_null
GPU  = gpu_unai
SPU  = spu_pcsxrearmed

RECOMPILER = mips

RM  = rm -f
MD  = mkdir
CC  = /opt/rs97-toolchain/bin/mipsel-linux-gcc
CXX = /opt/rs97-toolchain/bin/mipsel-linux-g++
LD  = /opt/rs97-toolchain/bin/mipsel-linux-g++

SYSROOT    := $(shell $(CC) --print-sysroot)
SDL_CONFIG := $(SYSROOT)/usr/bin/sdl-config
SDL_CFLAGS := $(shell $(SDL_CONFIG) --cflags)
SDL_LIBS   := $(shell $(SDL_CONFIG) --libs)

MCD1_FILE = \"mcd001.mcr\"
MCD2_FILE = \"mcd002.mcr\"

ifdef A320
	C_ARCH = -mips32 -msoft-float -DTMPFS_MIRRORING -DTMPFS_DIR=\"/tmp\"
endif

ifdef RS97
  C_ARCH = -mips32 -DDYNAREC_SKIP_DCACHE_FLUSH -DTMPFS_MIRRORING -DTMPFS_DIR=\"/tmp\" -DRS97 -I/opt/rs97_toolchain/os/usr/mipsel-buildroot-linux-uclibc/sysroot/usr/include/SDL -fsingle-precision-constant -mplt
endif

ifdef GCW0
	C_ARCH = -mips32r2 -DSHMEM_MIRRORING
endif

CFLAGS = $(C_ARCH) -mno-shared -mplt -mno-mips16 -O3 -DGCW_ZERO \
	-Wall -Wunused -Wpointer-arith \
	-Wno-sign-compare -Wno-cast-align \
	-Isrc -Isrc/spu/$(SPU) -D$(SPU) -Isrc/gpu/$(GPU) \
	-Isrc/port/$(PORT) \
	-Isrc/plugin_lib \
	-DXA_HACK \
	-DINLINE="static __inline__" -Dasm="__asm__ __volatile__" \
	$(SDL_CFLAGS)

# Convert plugin names to uppercase and make them CFLAG defines
CFLAGS += -D$(shell echo $(GPU) | tr a-z A-Z)
CFLAGS += -D$(shell echo $(SPU) | tr a-z A-Z)

ifdef RECOMPILER
CFLAGS += -DPSXREC -D$(RECOMPILER)
endif

CFLAGS += -fdata-sections -ffunction-sections
LDFLAGS = $(SDL_LIBS) -lSDL_mixer -lSDL_image -lrt -lz -lc -Wl,--as-needed -Wl,--gc-sections -flto -s

OBJDIRS = obj obj/gpu obj/gpu/$(GPU) obj/spu obj/spu/$(SPU) \
	  obj/recompiler obj/recompiler/$(RECOMPILER) \
	  obj/port obj/port/$(PORT) \
	  obj/plugin_lib

all: maketree $(TARGET)

OBJS = \
	obj/r3000a.o obj/misc.o obj/plugins.o obj/psxmem.o obj/psxhw.o \
	obj/psxcounters.o obj/psxdma.o obj/psxbios.o obj/psxhle.o obj/psxevents.o \
	obj/psxcommon.o \
	obj/plugin_lib/plugin_lib.o obj/plugin_lib/pl_sshot.o \
	obj/psxinterpreter.o \
	obj/mdec.o obj/decode_xa.o \
	obj/cdriso.o obj/cdrom.o obj/ppf.o \
	obj/sio.o obj/pad.o

ifdef RECOMPILER
OBJS += \
	obj/recompiler/mips/recompiler.o \
	obj/recompiler/mips/mips_disasm.o
endif

######################################################################
#  GPULIB from PCSX Rearmed:
#  Fixes many game incompatibilities and centralizes/improves many
#  things that once were the responsibility of individual GPU plugins.
#  NOTE: For now, only GPU Unai has been adapted.
ifeq ($(USE_GPULIB),1)
CFLAGS += -DUSE_GPULIB
OBJDIRS += obj/gpu/gpulib
OBJS += obj/gpu/$(GPU)/gpulib_if.o
OBJS += obj/gpu/gpulib/gpu.o obj/gpu/gpulib/vout_port.o
else
OBJS += obj/gpu/$(GPU)/gpu.o
endif
######################################################################

OBJS += obj/gte.o
OBJS += obj/spu/$(SPU)/spu.o

OBJS += obj/port/$(PORT)/port.o
OBJS += obj/port/$(PORT)/frontend.o

OBJS += obj/plugin_lib/perfmon.o

#******************************************
# spu_pcsxrearmed section BEGIN
#******************************************

##########
# Use a non-default SPU update frequency for these slower devices
#  to avoid audio dropouts. 0: once-per-frame (default)   5: 32-times-per-frame
#
#  On slower Dingoo A320, update 8 times per frame
ifdef A320
CFLAGS += -DSPU_UPDATE_FREQ_DEFAULT=3
endif

ifdef RS97
CFLAGS += -DSPU_UPDATE_FREQ_DEFAULT=3
endif

ifdef GCW0
#  On faster GCW Zero platform, update 4 times per frame
CFLAGS += -DSPU_UPDATE_FREQ_DEFAULT=2
endif
##########

##########
# Similarly, set higher XA audio update frequency for slower devices
#
#  On slower Dingoo A320, force XA to update 8 times per frame (val 4)
ifdef A320
CFLAGS += -DFORCED_XA_UPDATES_DEFAULT=4
endif

ifdef RS97
CFLAGS += -DFORCED_XA_UPDATES_DEFAULT=4
endif

ifdef GCW0
#  On faster GCW Zero platform, use auto-update
CFLAGS += -DFORCED_XA_UPDATES_DEFAULT=1
endif
##########

ifeq ($(SPU),spu_pcsxrearmed)
# Specify which audio backend to use:
SOUND_DRIVERS=sdl
#SOUND_DRIVERS=alsa
#SOUND_DRIVERS=oss
#SOUND_DRIVERS=pulseaudio

# Note: obj/spu/spu_pcsxrearmed/spu.o will already have been added to OBJS
#		list previously in Makefile
OBJS += obj/spu/spu_pcsxrearmed/dma.o obj/spu/spu_pcsxrearmed/freeze.o \
	obj/spu/spu_pcsxrearmed/out.o obj/spu/spu_pcsxrearmed/nullsnd.o \
	obj/spu/spu_pcsxrearmed/registers.o
ifeq "$(ARCH)" "arm"
OBJS += obj/spu/spu_pcsxrearmed/arm_utils.o
endif
ifeq "$(HAVE_C64_TOOLS)" "1"
obj/spu/spu_pcsxrearmed/spu.o: CFLAGS += -DC64X_DSP
obj/spu/spu_pcsxrearmed/spu.o: obj/spu/spu_pcsxrearmed/spu_c64x.c
frontend/menu.o: CFLAGS += -DC64X_DSP
endif
ifneq ($(findstring oss,$(SOUND_DRIVERS)),)
obj/spu/spu_pcsxrearmed/out.o: CFLAGS += -DHAVE_OSS
OBJS += obj/spu/spu_pcsxrearmed/oss.o
endif
ifneq ($(findstring alsa,$(SOUND_DRIVERS)),)
obj/spu/spu_pcsxrearmed/out.o: CFLAGS += -DHAVE_ALSA
OBJS += obj/spu/spu_pcsxrearmed/alsa.o
LDFLAGS += -lasound
endif
ifneq ($(findstring sdl,$(SOUND_DRIVERS)),)
obj/spu/spu_pcsxrearmed/out.o: CFLAGS += -DHAVE_SDL
OBJS += obj/spu/spu_pcsxrearmed/sdl.o
endif
ifneq ($(findstring pulseaudio,$(SOUND_DRIVERS)),)
obj/spu/spu_pcsxrearmed/out.o: CFLAGS += -DHAVE_PULSE
OBJS += obj/spu/spu_pcsxrearmed/pulseaudio.o
endif
ifneq ($(findstring libretro,$(SOUND_DRIVERS)),)
obj/spu/spu_pcsxrearmed/out.o: CFLAGS += -DHAVE_LIBRETRO
endif

endif
#******************************************
# spu_pcsxrearmed END
#******************************************

CXXFLAGS := $(CFLAGS) -fno-rtti -fno-exceptions

#If V=1 was passed to 'make', do not hide commands:
ifdef V
	HIDECMD:=
else
	HIDECMD:=@
endif

$(TARGET): $(OBJS)
	@echo Linking $(TARGET)...
	$(HIDECMD)$(LD) $(OBJS) $(LDFLAGS) -o $@

obj/%.o: src/%.c
	@echo Compiling $<...
	$(HIDECMD)$(CC) $(CFLAGS) -c $< -o $@

obj/%.o: src/%.cpp
	@echo Compiling $<...
	$(HIDECMD)$(CXX) $(CXXFLAGS) -c $< -o $@

obj/%.o: src/%.s
	@echo Compiling $<...
	$(HIDECMD)$(CXX) $(CFLAGS) -c $< -o $@

obj/%.o: src/%.S
	@echo Compiling $<...
	$(HIDECMD)$(CXX) $(CFLAGS) -c $< -o $@

$(sort $(OBJDIRS)):
	$(HIDECMD)$(MD) $@

maketree: $(sort $(OBJDIRS))

clean:
	$(RM) -r obj
	$(RM) $(TARGET)
