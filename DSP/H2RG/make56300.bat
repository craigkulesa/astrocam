..\clas563\bin\asm56300 -b -d DOWNLOAD HOST -ltim.ls tim.asm
..\clas563\bin\dsplnk -btim.cld -v tim.cln
del tim.lod
..\clas563\bin\cldlod tim.cld > tim.lod
del tim.cln
del tim.cld
rem ..\clas56\bin\srec -bs tim.lod
rem move tim.lod tim.rom
