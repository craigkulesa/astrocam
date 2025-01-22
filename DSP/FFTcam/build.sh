#!/bin/bash
	echo ""
	echo "Assembling DSP code for SDSU controller"
	echo ""

#export DYLD_FALLBACK_LIBRARY_PATH=/usr/X11/lib
#WAVEFORM_FILE=H2RG.waveforms

# either HOST or ROM
DOWNLOAD=HOST

if [ $DOWNLOAD == 'HOST' ]; then 
    PREFIX=tim
elif [ $DOWNLOAD == 'ROM' ]; then
    PREFIX=timboot
else
    echo "Invalid Download option: must be HOST or ROM."
    exit 1
fi

wine ../CLAS563/BIN/ASM56300.EXE -b -l"$PREFIX".ls -d DOWNLOAD $DOWNLOAD "$PREFIX".asm
wine ../CLAS563/BIN/DSPLNK.EXE -b"$PREFIX".cld -v "$PREFIX".cln 
rm -f "$PREFIX".lod
wine ../CLAS563/BIN/CLDLOD.EXE "$PREFIX".cld > "$PREFIX".lod
rm *.cln *.cld *.ls
if [ $DOWNLOAD == 'ROM' ]; then
    wine ../CLAS56/BIN/SREC.EXE -bs "$PREFIX".lod
    rm -f "$PREFIX".lod 
    echo "Created file '"$PREFIX".s' for EEPROM burning"    
elif [ $DOWNLOAD == 'HOST' ]; then 
    dos2unix "$PREFIX".lod
    echo "Created file '"$PREFIX".lod' for downloading over optical fiber"
fi
