
   PAGE    132     ; Printronix page width - 132 columns

; Include the boot and header files so addressing is easy
	INCLUDE "timhdr.asm"
	INCLUDE	"timboot.asm"

	ORG	P:,P:

CC	EQU	TIMREV5+IRX8VP+SUBARRAY

; Put number of words of application in P: for loading application from EEPROM
	DC	TIMBOOT_X_MEMORY-@LCV(L)-1

;******************  Read out the Array(s)  **************************
; Check for a command once per frame. Only the ABORT command should be issued.
RD_ARRAY
	BSET	#ST_RDC,X:<STATUS 	; Set status to reading out
	JSR	<PCI_READ_IMAGE		; Tell the PCI card the number of pixels to expect
	JSET	#TST_IMG,X:STATUS,SYNTHETIC_IMAGE

	MOVE	#$0c1000,A		; Reset FIFOs
	JSR	<WR_BIAS
	MOVE	#ENABLE_READ,R0		; Set the READEN signal high
	JSR	<CLOCK
	JSR	<CLOCK_H2RG		; Clock out the array normally
	
; Restore the controller to non-image data transfer and idling if necessary
RDA_END	MOVE	#CONT_RST,R0		; Continuously read array in idle mode
	MOVE	R0,X:<IDL_ADR
	JSR	<WAIT_TO_FINISH_CLOCKING
	BCLR	#ST_RDC,X:<STATUS	; Set status to not reading out
        RTS

;*********  Clock out the Array(s), either read or reset  *************
; The clocking for the H2RG is in a separate subroutine so it can be called
;   by both the read and the reset functions. 
CLOCK_H2RG
	MOVE    #FRAME_INIT,R0		; Initialize the frame for readout
	JSR     <CLOCK			;  and clock the first row

; Read the entire frame, clocking each row
	DO	Y:<NROWS_CLOCK,L_FRAME

	MOVE	#'BSY',X0
	JSSET	#ST_RST,X:STATUS,WRD_XMT
	
	DO	Y:<READ_DELAY,R_DELAY	; Delay by READ_DELAY microseconds
	MOVE	#ONE_MICROSEC_DELAY,R0
	JSR	<CLOCK
	NOP
R_DELAY

; H2RG requires 2 HCLK pulses before the first real pixel in each row
	MOVE	#FIRST_HCLKS,R0
	JSR	<CLOCK

; Finally, clock each row, read each pixel and transmit the A/D data
	DO	Y:<NCOLS_CLOCK,L_COLS
	MOVE	#CLK_COL,R0
	JSR	<CLOCK			; Clock each column
	NOP
L_COLS	NOP
	MOVE	#LAST_HCLKS,R0
	JSR	<CLOCK
	NOP
	MOVE    #CLOCK_ROW,R0 		; Clock each row
        JSR     <CLOCK
	NOP
L_FRAME
       	RTS
   	
WRD_XMT	MOVE	#$020002,B
	JSR	<XMT_WRD
	MOVE	X0,B
	JSR	<XMT_WRD
	RTS

;******************************************************************************
; Pixel-by-pixel reset, using the same timing as reading
RESET_ARRAY
	MOVE	#0,X0				; Disable transmitting A/Ds
	MOVE	X0,Y:<XMT_PXL
	MOVE	X0,Y:<XMT_PXL+2
	MOVE	X0,Y:<XMT_PXL+4
	MOVE	X0,Y:<XMT_PXL+6
	BSET	#ST_RST,X:<STATUS
	MOVE	#ENABLE_RESET,R0		; Set RESETEN signal high
	JSR	<CLOCK
	JSR	<CLOCK_H2RG			; Clock out array normally
	BCLR	#ST_RST,X:<STATUS
	RTS

;******************************************************************************       
; Continuously reset and read array, checking for commands each row
CONT_RST
	MOVE	#ENABLE_RESET,R0
	JSR	<CLOCK
	MOVE	#FRAME_INIT,R0
	JSR	<CLOCK
	DO	#1024,L_RESET		; Clock entire FPA
	MOVE	#CLOCK_ROW,R0		; Reset one row
	JSR	<CLOCK
	MOVE	#<COM_BUF,R3
	JSR	<GET_RCV		; Look for a new command every 4 rows
	JCC	<NO_COM			; If none, then stay here
	ENDDO
	JMP	<PRC_RCV
NO_COM	NOP
L_RESET
	JMP	<CONT_RST

; Include all the miscellaneous, generic support routines
	INCLUDE	"timIRmisc.asm"


TIMBOOT_X_MEMORY	EQU	@LCV(L)

;  ****************  Setup memory tables in X: space ********************

; Define the address in P: space where the table of constants begins

	IF	@SCP("DOWNLOAD","HOST")
	ORG     X:END_COMMAND_TABLE,X:END_COMMAND_TABLE
	ENDIF

	IF	@SCP("DOWNLOAD","ROM")
	ORG     X:END_COMMAND_TABLE,P:
	ENDIF

	DC	'SEX',START_EXPOSURE	; Voodoo and CCDTool start exposure
	DC      'PON',POWER_ON		; Turn on all camera biases and clocks
	DC      'POF',POWER_OFF		; Turn +/- 15V power supplies off
	DC	'SBN',SET_BIAS_NUMBER
	DC	'SMX',SET_MUX		; Set MUX number on clock driver board	
	DC      'DON',START
	DC	'SET',SET_EXPOSURE_TIME
	DC	'RET',READ_EXPOSURE_TIME
	DC	'AEX',ABORT_EXPOSURE
	DC	'ABR',ABR_RDC
	DC	'RCC',READ_CONTROLLER_CONFIGURATION 
	DC      'STP',STP		; Exit continuous reset mode
	DC	'IDL',IDLE		; Enable continuous reset mode
	
; NIRCam commands
	DC	'SER',SERIAL_COMMAND
	DC	'RIR',RESET_INTERNAL_REGISTERS		;
	DC	'CLR',CLR_ARRAY
	DC	'INI',INITIALIZE_H2RG_TO_NIRCAM		; New
	DC	'SSS',SET_SUBARRAY_SIZE			;
	DC	'SSP',SET_SUBARRAY_POSITION		;
	DC	'NUR',NUMBER_UP_THE_RAMP
	DC	'SRD',SET_READ_DELAY
	DC	'SNA',SET_NUMBER_OF_ARRAYS		;
	DC	'SVO',SET_VIDEO_OFFSET
	DC	'SOS',SELECT_OUTPUT_SOURCE		;
	
END_APPLICATON_COMMAND_TABLE	EQU	@LCV(L)

	IF	@SCP("DOWNLOAD","HOST")
NUM_COM			EQU	(@LCV(R)-COM_TBL_R)/2	; Number of boot + 
							;  application commands
EXPOSING		EQU	CHK_TIM			; Address if exposing
CONTINUE_READING	EQU	CONT_RD 		; Address if reading out
	ENDIF

	IF	@SCP("DOWNLOAD","ROM")
	ORG     Y:0,P:
	ENDIF

; Now let's go for the timing waveform tables
	IF	@SCP("DOWNLOAD","HOST")
        ORG     Y:0,Y:0
	ENDIF

GAIN	DC	END_APPLICATON_Y_MEMORY-@LCV(L)-1

NCOLS		DC	0		; Final image dimensions set by "voodoo"
NROWS		DC	0
NCOLS_ARRAY	DC	2048		; Number of columns in the physical array
NROWS_ARRAY	DC	2048		; Number of rows in the physical array
NCOLS_CLOCK	DC	0		; Number of columns clocked each frame
NROWS_CLOCK	DC	0		; Number of rows clocked each frame
NCOLS_XMIT	DC	0		; Number of columns transmitted per frame
NROWS_XMIT	DC	0		; Number of rows transmitted per frame
NSCA		DC	1		; Number of H2RG arrays in system (1 or 4)
NUTR		DC	1		; Number of up-the-ramp frames
CONFIG		DC	CC		; Controller configuration
READ_DELAY	DC	0		; Read delay in microsec
SEL_FPA		DC	$00F0C0		; SXMIT value for selected array
SEL_FPA_WM	DC	$00F000		; SXMIT value for selected array, WM

WM_NCOLS 	DC	0		; Windowing mode number of columns
WM_NROWS 	DC	0		; Windowing mode number of rows
WM_STARTCOL 	DC	0		; Windowing mode start column number
WM_STARTROW 	DC	0		; Windowing mode start row number

DUMMY	DC	$FFEECC

; Include the waveform table for the designated IR array
	INCLUDE "WAVEFORM_FILE" ; Readout and clocking waveform file

END_APPLICATON_Y_MEMORY	EQU	@LCV(L)

;  End of program
	END
