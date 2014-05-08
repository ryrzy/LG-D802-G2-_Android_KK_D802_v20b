#!/bin/bash
clear

# Initia script based on dorimanx script, thanks !

# What you need installed to compile
# gcc, gpp, cpp, c++, g++, lzma, lzop, ia32-libs

# What you need to make configuration easier by using xconfig
# qt4-dev, qmake-qt4, pkg-config

# Setting the toolchain
# the kernel/Makefile CROSS_COMPILE variable to match the download location of the
# bin/ folder of your toolchain
# toolchain already axist and set! in kernel git. android-toolchain/bin/

# Structure for building and using this script

#--project/				(progect container folder)
#------ramdisk/				(ramdisk files for boot.img)
#------kernel/				(kernel source goes here)
#--------OUTPUT/			(output directory, where the final boot.img is placed)
#----------meta-inf/			(meta-inf folder for your flashable zip)
#----------system/lib/modules/		(modules dir, will be added to system on boot)
#----------tmp/

# location
KERNELDIR=$(readlink -f .);

# begin by ensuring the required directory structure is complete, and empty
echo "Initialising................."
rm -rf "$KERNELDIR"/OUTPUT/boot
rm -f "$KERNELDIR"/OUTPUT/*.zip
rm -f "$KERNELDIR"/OUTPUT/*.img
mkdir -p "$KERNELDIR"/OUTPUT/boot

# force regeneration of .dtb and zImage files for every compile
rm -f arch/arm/boot/*.dtb
rm -f arch/arm/boot/*.cmd
rm -f arch/arm/boot/zImage
rm -f arch/arm/boot/Image

export PATH=$PATH:tools/lz4demo

# move into the kernel directory and compile the main image
echo "Compiling Kernel.............";
cp arch/arm/configs/g2_d802_yoda_defconfig .config

GETVER=$(grep 'CONFIG_LOCALVERSION="_Yoda_v.*' .config |sed 's/CONFIG_LOCALVERSION="_Yoda_v//g' | sed 's/.*".//g' | sed 's/".*//g');

# remove all old modules before compile
for i in $(find "$KERNELDIR"/ -name "*.ko"); do
        rm -f "$i";
done;

# build zImage
time make -j3

stat "$KERNELDIR"/arch/arm/boot/zImage || exit 1;

# compile the modules, and depmod to create the final zImage
echo "Compiling Modules............"
time make modules -j3 || exit 1

for i in $(find "$KERNELDIR" -name '*.ko'); do
        cp -av "$i" OUTPUT/system/lib/modules/;
done;

chmod 755 OUTPUT/system/lib/modules/*

if [ -e "$KERNELDIR"/arch/arm/boot/zImage ]; then

	cp arch/arm/boot/zImage OUTPUT/boot

	# create the ramdisk and move it to the output working directory
	echo "Create ramdisk..............."
	./scripts/mkbootfs ../ramdisk | gzip > ramdisk.gz 2>/dev/null
	mv ramdisk.gz OUTPUT/boot

	# create the dt.img from the compiled device files, necessary for msm8974 boot images
	echo "Create dt.img................"
	./scripts/dtbTool -v -s 2048 -o OUTPUT/boot/dt.img -p scripts/dtc/ arch/arm/boot/

	# build the final boot.img ready for inclusion in flashable zip
	echo "Build boot.img..............."
	cp scripts/mkbootimg_dtb OUTPUT/boot
	cd OUTPUT/boot
	base=0x00000000
	offset=0x05000000
	tags_addr=0x04800000
	pagesize=2048
	cmd_line="console=ttyHSL0,115200,n8 androidboot.hardware=g2 user_debug=31 msm_rtb.filter=0x0 mdss_mdp.panel=1:dsi:0:qcom,mdss_dsi_g2_lgd_cmd"

	./mkbootimg_dtb --kernel zImage --ramdisk ramdisk.gz --cmdline "$cmd_line" --base $base --pagesize $pagesize --ramdisk_offset $offset --tags_offset $tags_addr --dt dt.img -o newboot.img
	mv newboot.img ../boot.img

	# cleanup all temporary working files
	echo "Post build cleanup..........."
	cd ..
	rm -rf boot

	# create the flashable zip file from the contents of the output directory
	echo "Make flashable zip..........."
	zip -r Yoda_v"${GETVER}"_KK_Kernel_LG-D802"$(date +"[%d-%m]-[%H-%M]")".zip * >/dev/null
	stat boot.img
	rm -f ./*.img
	cd ..
else

	# with red-color
	 echo -e "\e[1;31mKernel STUCK in BUILD! no zImage exist\e[m"
fi;
