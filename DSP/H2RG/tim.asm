
   PAGE    132     ; Printronix page width - 132 columns

; Include the boot and header files so addressing is easy
	INCLUDE	"timboot.asm"

	ORG	P:,P:

CC	EQU	ARC22+ARC32+ARC46+TWO_XMTR+SUBARRAY+CONT_RD

; Put number of words of application in P: for loading application from EEPROM
	DC	TIMBOOT_X_MEMORY-@LCV(L)-1

ST_RDM		EQU	19	; Set if reading video channels one-by-one
ST_RST_MODE 	EQU	20	; Set if array needs resetting in continuous readout mode
ST_WM		EQU	21	; Set if in native H2RG windowing mode
ST_RST		EQU	22	; Set if resetting the array
ST_XMT2		EQU	23	; Set if transmitting over two fiber optic links
RD_MODE		EQU	3

;******************  Read out the H2RG array  **************************
; Check for a command once per frame. Only the ABORT command should be issued.
RD_ARRAY
	BSET	#ST_RDC,X:<STATUS 			; Set status to reading out
	JSR	<WAIT_TO_FINISH_CLOCKING
	MOVE	#RESET_FIFOS,A				; Reset ARC-46 image data FIFOs
	JSR	<WR_BIAS
	JSR	<PCI_READ_IMAGE				; Tell the PCI card the number of pixels to expect

; Exercise the second fiber optic transmitter if needed
	JCLR    #ST_XMT2,X:STATUS,NO2XMT
	BSET    #1,X:PDRC				; Transmit image data on second fo xmtr
NO2XMT	JSET	#TST_IMG,X:STATUS,SYNTHETIC_IMAGE

	JSR	<CLOCK_H2RG			; Clock out the array normally

; This is code for continuous readout - check if more frames are needed
	MOVE	Y:<N_FRAMES,A			; Are we in continuous readout mode?
	CMP	#1,A
	JLE	<RDA_END
	BCLR	#ST_RDC,X:<STATUS		; Set status to not reading out
	JSR	<WAIT_TO_FINISH_CLOCKING

; Check for a command once. Only the ABORT command should be issued.
	MOVE	#COM_BUF,R3
	JSR	<GET_RCV			; Was a command received?
	JCC	<NEXT_FRAME			; If no, get the next frame
	JMP	<PRC_RCV			; If yes, go process it

; Restore the controller to non-image data transfer and idling if necessary
RDA_END	MOVE	#CONT_RST,R0			; Continuously read array in idle mode
	MOVE	R0,X:<IDL_ADR
	JSR	<WAIT_TO_FINISH_CLOCKING
	BCLR	#ST_RDC,X:<STATUS		; Set status to not reading out
	BCLR	#1,X:PDRC			; Restore single transmitter mode
        RTS

;*********  Clock out the H2RG array  *************
CLOCK_H2RG
	MOVE    #FRAME_INIT,R0				; Initialize the frame for readout
	JSR     <CLOCK

; Skip over the unread rows, if in sub-array, non-windowing mode
	JCLR	#ST_SA,X:STATUS,L_RSKIP
	JSET	#ST_WM,X:STATUS,L_RSKIP
	DO	Y:<SA_STARTROW,L_RSKIP
	MOVE	#SKIP_ROW,R0
	JSR	<CLOCK
	NOP
L_RSKIP 

; Read the entire frame, clocking each row
	DO	Y:<NROWS_CLOCK,L_FRAME
	MOVE    #CLOCK_ROW,R0 			; Clock each row
	JSR     <CLOCK

	DO	Y:<READ_DELAY,R_DELAY		; Delay by READ_DELAY microseconds
	MOVE	#ONE_MICROSEC_DELAY,R0
	JSR	<CLOCK
	NOP
R_DELAY

; Skip over the unread columns, if needed
	JCLR	#ST_SA,X:STATUS,L_CSKIP
	JSET	#ST_WM,X:STATUS,L_CSKIP
	DO	Y:<SA_NCOLS_CK,L_CSKIP
	MOVE	#SKIP_COL,R0
	JSR	<CLOCK
	NOP
L_CSKIP 

; H2RG requires 2 HCLK pulses before the first real pixel in each row
	MOVE	#FIRST_HCLKS,R0
	JSR	<CLOCK

; Finally, clock each row, read each pixel and transmit the A/D data
	DO	Y:<NCOLS_CLOCK,L_COLS
	MOVE	#CLK_COL,R0
	JSR	<CLOCK			; Clock and read each column
	NOP
L_COLS	NOP

	MOVE	#LAST_HCLKS,R0
	JSR	<CLOCK
	NOP
L_FRAME
	MOVE    #OVERCLOCK_ROW,R0 	; Extra row clock at the end of frame
	JSR     <CLOCK
       	RTS

;******************************************************************************
; Global reset
RESET_ARRAY
	BSET	#ST_RST,X:<STATUS
	MOVE	#GLOBAL_RESET,R0
	JSR	<CLOCK
	BCLR	#ST_RST,X:<STATUS
	RTS

; Continuously execute line-by-line reset array, checking for commands each line
CONT_RST
	;MOVE	#FRAME_INIT_RESET,R0
	;JSR	<CLOCK
	DO	#1024,L_RESET		; Clock entire FPA
	MOVE	#CLOCK_ROW_RESET,R0	; Reset one row
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
	DC	'PEX',PAUSE_EXPOSURE
	DC	'REX',RESUME_EXPOSURE
	DC	'AEX',ABORT_EXPOSURE
	DC	'ABR',ABORT_EXPOSURE
	DC	'RCC',READ_CONTROLLER_CONFIGURATION 
	DC      'STP',STP		; Exit continuous reset mode
	DC	'IDL',IDLE		; Enable continuous reset mode

; Continuous readout commands
	DC	'SNF',SET_NUMBER_OF_FRAMES
	DC	'FPB',SET_NUMBER_OF_FRAMES_PER_BUFFER

; Test the second fiber optic transmitter
	DC	'XMT',SELECT_DUAL_TRANSMITTER

; More commands
	DC	'SSS',SET_SUBARRAY_SIZE
	DC	'SSP',SET_SUBARRAY_POSITION
	DC	'SWM',SELECT_WINDOWING_MODE
	DC	'SNC',SPECIFY_NUMBER_OF_CHANNELS
	DC	'SER',SERIAL_COMMAND
	DC	'RIR',RESET_INTERNAL_REGISTERS
	DC	'CLR',CLR_ARRAY
	DC	'INI',INITIALIZE_H2RG
	DC	'SRM',SET_RESET_MODE
	DC	'VRM',VIDEO_READOUT_MODE		; One-by-one or all eight channels at once
	DC	'SRD',SET_READ_DELAY
	DC	'SVO',SET_VIDEO_OFFSET
	DC	'RNC',READ_NUMBER_OF_CHANNELS
	DC	'SVC',SELECT_VIDEO_CHANNEL_NUMBER
	DC	'CDS',CORRELATED_DOUBLE_SAMPLE

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

		DC	END_APPLICATON_Y_MEMORY-@LCV(L)-1

NCOLS		DC	0		; Image dimensions set by host computer
NROWS		DC	0
NCOLS_CLOCK	DC	0		; Number of columns clocked each frame
NROWS_CLOCK	DC	0		; Number of rows clocked each frame
CONFIG		DC	CC		; Controller configuration
READ_DELAY	DC	0		; Read delay in microsec
SXMIT		DC	$00F0C0		; Magic number for series transmit of image data
NCHS		DC	4		; Number of channels of readout
NUM_CHANS	DC	4		; Number of channels in not windowing mode
N_SHFTS		DC	2		; Number of readout channels as a power of 2

; Continuous readout parameters
N_FRAMES 	DC	1		; Total number of frames to read out
I_FRAME		DC	0		; Number of frames read out so far
IBUFFER		DC	0		; Number of frames read into the PCI buffer
N_FPB		DC	0		; Number of frames per PCI image buffer

; Subarray readout parameters
SA_NCOLS 	DC	0		; Number of columns in the image
SA_NROWS 	DC	0		; Number of rows in the image
SA_BEGCOL 	DC	0		; Beginning column number to read
SA_NCOLS_CK 	DC	0		; Number of clocks needed to skip over columns 
SA_STARTROW 	DC	0		; Beginning row number to read

; Include the waveform table for the designated IR array
	INCLUDE "WAVEFORM_FILE" ; Readout and clocking waveform file

END_APPLICATON_Y_MEMORY	EQU	@LCV(L)

;  End of program
	END
