#!/bin/sh
	echo ""
	echo "Assembling DSP code for SDSU GENII controller"
	echo ""

export DYLD_FALLBACK_LIBRARY_PATH=/usr/X11/lib
# either HOST or ROM
DOWNLOAD=HOST

if [ $DOWNLOAD == 'HOST' ]; then 
    PREFIX=RxTx
elif [ $DOWNLOAD == 'ROM' ]; then
    PREFIX=timboot
else
    echo "Invalid Download option: must be HOST or ROM."
    exit 1
fi

wine ../CLAS56/BIN/ASM56000 -b -l"$PREFIX".ls -d DOWNLOAD $DOWNLOAD -d OUTPUTS 4 "$PREFIX".asm
if [ $DOWNLOAD == 'HOST' ]; then
    wine ../CLAS56/BIN/ASM56000 -b -ltimboot.ls timboot.asm
    wine ../CLAS56/BIN/ASM56000 -b -lsubarray.ls -d DOWNLOAD HOST -d QUAD 2 subarray.asm
    wine ../CLAS56/BIN/DSPLNK -b"$PREFIX".cld -v "$PREFIX".cln timboot.cln subarray.cln
else
# fixme when load files work...
    wine ../CLAS56/BIN/ASM56000 -b -lRxTx.ls -d DOWNLOAD $DOWNLOAD -d OUTPUTS \
4 RxTx.asm
    wine ../CLAS56/BIN/ASM56000 -b -lsubarray.ls -d DOWNLOAD EEPROM -d QUAD 2 subarray.asm
    wine ../CLAS56/BIN/DSPLNK -b"$PREFIX".cld -v "$PREFIX".cln RxTx.cln subarray.cln
fi 

rm -f "$PREFIX".lod
wine ../CLAS56/BIN/CLDLOD "$PREFIX".cld > "$PREFIX".lod
rm *.cln *.cld *.ls

if [ $DOWNLOAD == 'ROM' ]; then
    wine ../CLAS56/BIN/SREC -bs "$PREFIX".lod
    rm -f "$PREFIX".lod 
    echo "Created file '"$PREFIX".s' for EEPROM burning"    
elif [ $DOWNLOAD == 'HOST' ]; then 
    dos2unix "$PREFIX".lod
    mv "$PREFIX".lod tim.lod
    echo "Created file 'tim.lod' for downloading over optical fiber"
fi
