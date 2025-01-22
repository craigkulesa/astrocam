
   PAGE    132     ; Printronix page width - 132 columns
   OPT	CEX	; print DC evaluations

; Include the boot and header files so addressing is easy
	INCLUDE	"timboot.asm"

	ORG	P:,P:

CC	EQU	ARC22+ARC32+ARC46+SUBARRAY+CONT_RD

; Put number of words of application in P: for loading application from EEPROM
	DC	TIMBOOT_X_MEMORY-@LCV(L)-1

ST_RDM		EQU	19	; Set if reading video channels one-by-one
ST_RST_MODE 	EQU	20	; Set if array needs resetting in continuous readout mode
ST_WM		EQU	21	; Set if in native H2RG windowing mode
ST_RST		EQU	22	; Set if resetting the array
ST_XMT2		EQU	23	; Set if transmitting over two fiber optic links
RD_MODE		EQU	3

; Port D bits
SCK	EQU	3		; Serial transmitter clock

; I don't think we need these anymore
; X: status word bits
;IDLM	EQU	0	; Set if in idle mode => clocking out
;RCV_FO	EQU	2	; Set if received message is from the FO, cleared if SCI

DUALCLK	EQU	1

; *****  Clocking macros  *****
; R0 contains address of waveform table.
; Define as macros to produce in-line code to reduce execution time

CLOCK1	MACRO
	JCLR	#SSFHF,X:HDR,*	; Don't overfill the WRSS FIFO
	MOVEP	Y:(R0),Y:WRSS	; Write the waveform to the FIFO
	ENDM

CLOCK2	MACRO
	JCLR	#SSFHF,X:HDR,*	; Don't overfill the WRSS FIFO
	MOVEP	Y:(R0)+,Y:WRSS	; Write the waveform to the FIFO
	MOVEP	Y:(R0),Y:WRSS	; Write the waveform to the FIFO
	ENDM
	
; X0 contains number of waveform entries, R0 contains address of waveform table.
; Define as macros to produce in-line code to reduce execution time

CLOCK	MACRO
	JCLR	#SSFHF,X:HDR,*	; Don't overfill the WRSS FIFO
	REP	X0		; Repeat for each waveform entry
	MOVEP	Y:(R0)+,Y:WRSS	; Write the waveform entry to the FIFO
	ENDM


; *****  Idle  *****
; Keep the array idling when not reading out.

IDLE	BSET	#IDLING,Y:<T_STATUS	; Revise status
;	MOVE	#<MSG_BUF,R3		; Reset message buffer pointer
;	BCLR	#CMD_RCV,Y:FLAGREG	; Clear command received flag
;	JSR	<SMP_WT		; Check for commands and clock array
;	JSET	#CMD_RCV,Y:FLAGREG,PRC_RCV	; If command, process it
	MOVE	#<COM_BUF,R3
    JSR         <GET_RCV                          ; Check for commands
    JCS         <PRC_RCV                          ; If command, process it


;WAIT_RD NOP
;	NOP
;	BCLR #IDLING,Y:<T_TRIGGER
	
;	JCLR #EXT_IN0,X:HDR,WAIT_RD		; Wait for the trigger to go low
	
;	BSET #IDLING,Y:<T_TRIGGER
	
;	JCLR #EXT_IN0,X:HDR,WAIT_RD		; If trigger is high start all over
	


	JSR DLY1US
	
	JSR	<RST_ARRAY	; Reset array
	
	JSR DLY1US
	
	MOVE	#<ST_FRM,R0	; Pulse FDEM
	CLOCK2
	
	DO	Y:<IDLCKS,IDL1	; Loop over number of pixels

	MOVE	#START_MIMIC_ADC,R0
	NOP
	NOP
	NOP
	MOVE	Y:(R0)+,X0
	CLOCK
	NOP
	
	
;	MOVE	#<IDL_DLY,R0	; Delay to match readout
;	CLOCK1
	NOP
IDL1

	

        JMP	<IDLE



; ***** Let PCI board know how much data is coming *****
; The PCI board expects two values, nominally an "x" and "y" size, which it
; multiplies together internally to get the total array size. Unfortunately, 
; due to the pipeline architecture of the ADCs, the total number of pixel 
; values transmitted is greater than the specified raster size. Therefore, 
; these values are kluged to produce two numbers that, when multiplied
; together, give the correct total number.

PCI_READ_IMAGE

	MOVE	Y:IIA_HDR,B	; Send 'IIA' command to PCI board to clear pixel count
	JSR	<XMT_WRD
	MOVE	Y:IIA_CMD,B
	JSR	<XMT_WRD

;	MOVE	#<IDL_DLY,R0	; Delay between commands
;	CLOCK1

	JSR <DLY10US

	MOVE	Y:RDA_HDR,B	; Send 'RDA' command to PCI board to intialize pixel count
	JSR	<XMT_WRD
	MOVE	Y:RDA_CMD,B
	JSR	<XMT_WRD
	MOVE	Y:NPCI_X,B	; Number of "columns" to read
	JSR	<XMT_WRD
	MOVE	Y:NPCI_Y,B	; Number of "rows" to read
	JSR	<XMT_WRD
	RTS


SET_EXPOSURE_TIME JMP <FINISH

; *****  Readout Array  *****
; Do a single frame readout according to the current parameter set. 
; Only external reference subtraction mode is supported.

RD_ARRAY
	MOVE	#<ST_FRM,R0	; Pulse FDEM
	CLOCK2

; Read raster
	DO	Y:YRAS,LYRAS
	NOP
; Read out one row in the X direction

	MOVE #ROW_START,R0 ; extra long clock (ROW_START waveform) at beginning of each row
	CLOCK1

	DO	Y:XBLK,LXBLK
	NOP			; DO loop restriction

; Start next ADC conversion
	MOVE	#START_ADC,R0	; Start conversion sample n, latch sample n-2
	NOP
	NOP
	NOP
	MOVE	Y:(R0)+,X0
	CLOCK
	NOP

LXBLK	; End of one row

; One extra clock required at end of row
	MOVE	#START_MIMIC_ADC,R0 
	NOP			    
	NOP
	NOP
	MOVE	Y:(R0)+,X0
	CLOCK			
	NOP

LYRAS	; End of subraster

	MOVE	#START_MIMIC_ADC,R0
	NOP
	NOP
	NOP
	MOVE	Y:(R0)+,X0
	CLOCK
	NOP
	
	RTS		; return



; *****  Readout Command *****
; Readout image initiated by SEX Command.

START_EXPOSURE
	BCLR	#IDLING,Y:<T_STATUS	; Revise status
	BSET	#RDCBUSY,Y:<T_STATUS
	MOVE	Y:<T_NUM_RST,A
	TST	A		; check for zero
	JEQ	<NO_RST
	MOVE	A,Y:RSTCNT
	BSET	#REFFRM,Y:<FLAGREG	; set flag for reference frame
NO_RST	NOP

; Send readout notification to PCI board
	JSR	<PCI_READ_IMAGE		; get PCI reading image
	JSR	<RST_ARRAY		; reset array
	JSR	<RD_ARRAY		; read array

	MOVE	Y:<SAMPLES,A
	SUB #1,A
	NOP

	DO	A,SUTRLP
	; Start the exposure timer // trigger code goes here
	MOVEP	#0,X:TLR0		; Load 0 into counter timer
	MOVE	Y:<T_EXP_TIM,B
	TST	B			; Special test for zero exposure time
	JEQ	<ENDIT1			; Don't even start an exposure
	SUB	#1,B			; Timer counts from X:TCPR0+1 to zero
	BSET	#TIM_BIT,X:TCSR0	; Enable the timer #0
	MOVE	B,X:TCPR0
	JCLR	#TCF,X:TCSR0,*		; Wait for timer to equal compare value
;	JSET #EXT_IN0,X:HDR,*		; Wait for the trigger to go low (lines above for regular readout)
ENDIT1	BCLR	#TIM_BIT,X:TCSR0	; Disable the timer
	JSR	<RD_ARRAY		; read array
	NOP
SUTRLP

; Cleanup and return
RDCDON	BCLR	#ABTEXP,Y:<FLAGREG	; Clear ABT request
	BCLR	#RDCBUSY,Y:<T_STATUS	; Clear readout status
	
	MOVE	#>1000,A
	JSR	<MICROSEC_DELAY		; Wait one millisecond to finish transferring data before switching to single fiber


;//	JMP <IDLE
	JMP <FINISH


; *****  Wait for sample time  *****
; This routine is executed while idling and while waiting for the sample time
; during an exposure. It continuously runs the pixel clock and checks for
; new commands from the host while waiting for the exposure time to expire

;CHK_TIM	JCLR	#TCF,X:TCSR0,SMP_WT2	; If not done, continue exposing
CHK_TIM  NOP


; *****  Load Parameters  *****
; The LDP command copies the parameters from the input buffer to the working 
; parameter table and puts them into effect.

LOAD_PARAMETERS	BCLR	#LDPFLG,Y:<FLAGREG	; Clear load parameters flag

; Check mode selection 
;;	JSET	#FOWLER,Y:<T_MODE,LDP_ERR	; error if Fowler
;;	JCLR	#EXTREFSUB,Y:<T_MODE,LDP_ERR	; error if not external ref sub

; Copy parameters from input table
	MOVE    #<P_BUF,R0	; address of parameter table
	MOVE    #<PARMID,R7	; address of current parameter set
	NOP			; Register access restriction
	NOP			; Register access restriction
	MOVE    Y:(R0)+,X0	; # of parameter table entries 
	DO      X0,LDPLP	; Repeat X0 times
	MOVE    Y:(R0)+,A	; Get new parameter
	NOP			; Register access restriction
	MOVE    A,Y:(R7)+	; Write new parameter
LDPLP

; Calculate number of pixels per image
CALNPX	MOVE	Y:<NPIXEL,A	; get number of pixels in frame
	MOVE	Y:<NPLPX,X0
	ADD	X0,A Y:<ZERO,X1	; Add twelve for pipeline pixels
	MOVE	Y:PXSAMP,Y0
	MOVE	A,Y:<NPXSEND	; # pixels to process = NPIXEL+NPLPX
	MOVE	A,Y1
	MPY	Y1,Y0,A		; multiply by number of pixel samples
	ASR	A		; correct for MPY
	NOP			; Register access restriction
	MOVE	A0,Y:<NPXCLR	; # entries to clear in buffer = (NPIXEL+NPLPX)*PXSAMP
	REP	#4
	ASR	A		; divide by 16
	NOP			; Register access restriction
	MOVE	A0,Y:<NPCI_X	; "x" value to initialize PCI count
				; = ((NPIXEL+NPLPX)*PXSAMP)/16 ;16 for UofT
	MOVE	Y:<SAMPLES,A
	REP #4
	ASL	A
	NOP			; Register access restriction
	MOVE	A,Y:<NPCI_Y	; "y" value to initialize PCI count = 16*SAMPLES

; Calculate number of pixels at the end of each row (XTAIL)
	MOVE	Y:<XRAS,A
	REP	#4
	ASR	A		; Divide by 16 for # blocks
	NOP			; Register access restriction
	MOVE	A,Y:<XBLK	; XBLK = XRAS / 8 ; 16 for UofT
	MOVE	A,Y0
	MOVE	Y:<XSTART,A
	REP	#4
	ASR	A		; Divide by 16 for # blocks
	NOP			; Register access restriction
	MOVE	A,Y:<XSTBLK	; XSTBLK = XSTART / 16	
	ADD	Y0,A
	NOP			; Register access restriction
	MOVE	A,Y0
	MOVE	Y:<T_XSIZE,A
	REP	#4
	ASR	A		; Divide by 16 for # blocks
	SUB	Y0,A
	NOP			; Register access restriction
	MOVE	A,Y:<XTAIL	; XTAIL= (XSIZE/4)-((XSTART/4)+(XRAS/4))

; Calculate number of pixels at the end of each column (YTAIL)
	MOVE	Y:<YRAS,A
	MOVE	Y:<YSTART,Y0
	ADD	Y0,A
	NOP			; Register access restriction
	MOVE	A,Y0
	MOVE	Y:<T_YSIZE,A
	SUB	Y0,A
	NOP			; Register access restriction
	MOVE	A,Y:<YTAIL	; YTAIL= YSIZE-(YSTART+YRAS)

; Calculate number of clocks in idle mode = ((cols/outputs)+1)*rows+1
	MOVE	Y:<NPIXEL,A
	REP	#4
	ASR	A		; Divide by 16 for # blocks
	MOVE	Y:<YRAS,Y1
	ADD	Y1,A X:<ONE,X1
	ADD	X1,A
	NOP			; Register access restriction
	MOVE	A,Y:IDLCKS	; IDLCKS = NPIXEL/16+YRAS+1

; Set up SAPHIRA control registers
	MOVE	Y:DCR_REG,B	; get DCR setting
	BSET	#MCRBIT,B1	; set MCR register next
	JSR	SET_CR		; go send the data
	BSET	#MCR_SET,Y:<FLAGREG	; set flag to indicate MCR write
	MOVE	Y:MCR_REG,B	; get MCR setting
	JSR	SET_CR		; go send the data

; Set up windowing registers
	MOVE	Y:DCR_REG,B	; get DCR setting
	BSET	#WDRBIT,B1	; set WDR register next
	JSR	SET_CR		; go send the data
	JSR	SET_WR		; go send the data
	
	MOVE	Y:DCR_REG,B	; get DCR setting
	BSET	#WRRBIT,B1	; set WRR register next
	JSR	SET_CR		; go send the data
	JSR	SET_WR		; go send the data
;	JSR	WRRRST		; go send the data (DEBUG)

	MOVE	Y:DCR_REG,B	; get DCR setting (no more registers)
	JSR	SET_CR		; go send the data

	JMP	<FINISH		; send DON reply

LDP_ERR	BSET	#BAD_MD,Y:T_ERROR	; Flag bad mode setting
	MOVE	Y:ERR_RPL,X0		; Send the message - there was an error
	JMP	<FINISH1


; *****  Initialize  *****
; Set control voltages and configuration of video and clock boards
; Power up sequence:
;  VDD -> VDDPIX, VDDA, VDD_OP -> PRV -> POR

INIT_SAPHIRA	BSET	#IDLMODE,X:<STATUS		; force into idling mode	
	MOVEP	#50,X:TPLR				; microsec timer setup

; Set timing board latch signals
	MOVE	Y:LTC_INI,X0		; Get initial latch state
	MOVE	X0,X:<LATCH
	BCLR	#CDAC,X:<LATCH		; Clear of DAC settings
	BCLR	#DUALCLK,X:<LATCH	; Don't clk 2 halves of clk bd together
	BCLR	#ENCK,X:<LATCH		; Open clock and DAC output switches
	MOVEP	X:LATCH,Y:WRLATCH 	; Write to latch
	JSR	<DLY10US
	JSR	<DLY10US
	BSET	#CDAC,X:<LATCH		; Disable clearing of DACs
	MOVEP	X:LATCH,Y:WRLATCH 	; Write to latch
	JSR	<DLY10US
	JSR	<DLY10US
	BCLR	#ST_RDM,X:<STATUS
	BCLR	#RD_MODE,X:<LATCH
	MOVEP	X:LATCH,Y:WRLATCH	; Write the bit to the IR video PAL
	
; Set up serial port
	BSET	#SCK,X:PCRD	; Turn the serial clock on

; Clear clock board switches
	MOVE	#<POR_0A,R0	; Set all switch states to 0 (CLKA)
	CLOCK1
	MOVE	#<POR_0B,R0	; Set all switch states to 0 (CLKB)
	CLOCK1

;; Set clock driver DACs (includes VDD supplies)
	MOVE	#CLKDACS,R0	; Get starting address of DAC values
	JSR	<SET_DAC

	MOVE	#>25000,A
	JSR	<MICROSEC_DELAY		; Wait three milliseconds

; Close output switches
	BSET	#ENCK,X:<LATCH		; Close clock and DAC output switches
	MOVEP	X:LATCH,Y:WRLATCH

; Turn on the VDD supplies in sequence
	MOVE	#<POR_1,R0	; VDD
	CLOCK1
	
	MOVE	#>25000,A
	JSR	<MICROSEC_DELAY		; Wait three milliseconds

	MOVE	#<POR_2,R0	; VDDPIX, VDDA, VDD_OP
	CLOCK1
	
	MOVE	#>25000,A
	JSR	<MICROSEC_DELAY		; Wait three milliseconds
	
; Set bias voltage DACs 
	MOVE	#DC_BIASES,R0		; Get starting address of DAC values
	JSR	<SET_DAC
	
	MOVE	#>25000,A
	JSR	<MICROSEC_DELAY		; Wait three milliseconds

	MOVE	#AV_BIASES,R0  ;MOVE	#HV_BIASES,R0
	JSR <SET_DAC           ;JSR <SET_DAC
	
	MOVE	#>25000,A
	JSR	<MICROSEC_DELAY		; Wait three milliseconds

; Deactivate power on reset
	MOVE	#<POR_3,R0	; POR
	CLOCK1

; Clear the T_ERROR status word
	CLR	A
	NOP			; Register access restriction
	MOVE	A1,Y:<T_ERROR

	BCLR	#SCK,X:PCRD	; Turn the serial clock off

; Turn off status LED to reduce stray light
	BSET	#LED1,X:HDR	; Turn off LED

; Load default parameters and return
	JMP	<LOAD_PARAMETERS

; Send DON reply
;	JMP	<FINISH



; *****  Clear Array  *****
; Reset array  (initiated by CLR command)

CLR_ARRAY	JSR	<RST_ARRAY
	JMP	<FINISH		; Send out 'DON' reply



; *****  Set software to IDLE mode  *****
; Causes the timing board to continuously clock the array while waiting for
; commands.

IDL	BSET	#IDLMODE,X:<STATUS
	JMP	<FINISH	



; *****  Take software out of IDLE mode  *****
; Stops the timing board from clocking the array while waiting for commands.
; It is important to do so before downloading new timing board application code
; so that the board does not attempt to execute half-loaded code.

STP	BCLR	#IDLMODE,X:<STATUS
	BCLR	#IDLING,Y:<T_STATUS
	JMP	<FINISH



; *****  Power Off (POF)  *****
; Turn off the analog power supplies
POWER_OFF
	JSET	#EXPING,Y:T_STATUS,SND_ERR	; ignore during exposure
;	JSR	<CLR_ASW	; Clear analog switches
;	BSET	#HVEN,X:HDR	; Turn off the power supplies

	; Set timing board latch signals
	MOVE	Y:LTC_INI,X0		; Get initial latch state
	MOVE	X0,X:<LATCH
	BCLR	#CDAC,X:<LATCH		; Clear of DAC settings
	BCLR	#DUALCLK,X:<LATCH	; Don't clk 2 halves of clk bd together
	BCLR	#ENCK,X:<LATCH		; Open clock and DAC output switches
	MOVEP	X:LATCH,Y:WRLATCH 	; Write to latch
	JSR	<DLY10US
	JSR	<DLY10US
	BSET	#CDAC,X:<LATCH		; Disable clearing of DACs
	MOVEP	X:LATCH,Y:WRLATCH 	; Write to latch
	JSR	<DLY10US
	JSR	<DLY10US
	BCLR	#ST_RDM,X:<STATUS
	BCLR	#RD_MODE,X:<LATCH
	MOVEP	X:LATCH,Y:WRLATCH	; Write the bit to the IR video PAL
	NOP
	
	MOVE	Y:LV_WAIT,A	; Delay for settling
	DO	A,PWDLY2
	JSR	DLY10US
	NOP
PWDLY2

	BSET	#LVEN,X:HDR
	JMP	<FINISH



; *****  Power On (PON)  *****
; Turn on the analog power supplies -- this should not bias anything on the array, which needs INI
POWER_ON
;	JSET	#EXPING,Y:T_STATUS,SND_ERR	; ignore during exposure
;	JSR	<CLR_ASW	; Clear analog switches
	BCLR	#IDLMODE,X:<STATUS	; Clear idle mode flag to stop idling

; Turn on the low voltages (+/- 6.5V, +/- 16.5V)
	BCLR	#LVEN,X:HDR	; LVEN = Low => Turn on +/-16V
	MOVE	Y:LV_WAIT,A	; Delay for settling
	DO	A,PWDLY1
	JSR	DLY10US
	NOP
PWDLY1
	
	MOVE	#ZERO_BIASES,R0  ; zero the video board biases
	JSR <SET_DAC
	NOP
	
; Test if the power turned on properly
;	JSET	#PWROK,X:HDR,INIT_SAPHIRA	; Go to initialisation if PWROK = 1
	JSET	#PWROK,X:HDR,FINISH	; if PWROK = 1, don't initialize yet; we need to wait for temperature in range before setting DACs.

; Power not okay - turn off power and send error reply
;	JSR	<CLR_ASW	; Clear analog switches
;	BSET	#HVEN,X:HDR	; Turn off the power supplies
	BSET	#LVEN,X:HDR
	MOVE	Y:POE_RPL,Y1	; Send the message - there was an error
	JMP	<FINISH1



; *****  Command Error  *****
; Send an error message if a command is received that is not available in
; the current status (e.g. while exposing)

SND_ERR
	MOVE	Y:<ERR_RPL,Y1	; Send the message - there was an error
	JMP	<FINISH1	; This protects against unknown commands



; ****************************  Subroutines  *******************************

; ***** Reset Array  *****
;  Reset the array with external reset

RST_ARRAY
	MOVE	#<RST_ARR,R0
	CLOCK1 
	
	MOVE	#<RST_PX,R0
	CLOCK2
	
	MOVE	#<RST_PX+2,R0	; 
	CLOCK1
	
	MOVE	#START_MIMIC_ADC,R0
	NOP
	NOP
	NOP
	MOVE	Y:(R0)+,X0
	CLOCK
	NOP
	
	REP	#100
	NOP

	RTS



; ***** Set DACs  *****
;  Update the DACs
SET_DAC MOVE	Y:(R0)+,X0	; Get the number of table entries
	NOP			; Register access restriction
	DO	X0,SET_L0	; Repeat X0 times
	MOVE	Y:(R0)+,A
	JSR	<XMIT_A_WORD	; Send
	JSR	<DLY10US	; delay for transmit
	NOP			; DO loop restriction
SET_L0
	RTS			; Return from subroutine


; ***** Run ADC *****
; One cycle of ADC
RUNADC MOVE	Y:(R0)+,X0 ; Get the number of table entries
	NOP
	DO X0,LOOPADC
	MOVE	Y:(R0)+,A
	JSR <XMIT_A_WORD
	JSR	<DLY10US
	NOP
LOOPADC
	RTS

; ***** One microsecond delay  *****
; 1 us delay 
DLY1US	REP	#100
	NOP
	RTS

; ***** Ten microsecond delay  *****
; 10 us delay 
DLY10US	REP	#1000
	NOP
	RTS

; ***** Microsec delay ****

MICROSEC_DELAY
	TST	A
	JNE	<DLY_IT
	RTS
DLY_IT	SUB	#1,A
	MOVEP	#0,X:TLR0		; Load 0 into counter timer
	BSET	#TIM_BIT,X:TCSR0	; Enable the timer #0
	MOVE	A,X:TCPR0		; Desired elapsed time
CNT_DWN	JCLR	#TCF,X:TCSR0,CNT_DWN	; Wait here for timer to count down
	BCLR	#TIM_BIT,X:TCSR0
	RTS


; *****  Write Control Register  *****
; Program an 8-bit control register via the SAPHIRA serial interface.
SET_CR	REP	#16
	LSL	B		; Shift data to left end of accumulator

	DO	#8,L_SER	; Send 8 bits, MSB first
	LSL	B		; Get next bit of data word
	JCC	<TX_BIT		; Check value of bit
	MOVE	#<SER_1,R0	; bit = 1
	CLOCK2
	JMP	<TX_DON
TX_BIT	MOVE	#<SER_0,R0	; bit = 0
	CLOCK2
TX_DON	NOP
L_SER

	JSET	#MCR_SET,Y:<FLAGREG,NO_NCS	; if MCR, do not set NCS high
	MOVE	#<END_SER,R0
	CLOCK2

NO_NCS	BCLR	#MCR_SET,Y:<FLAGREG	; clear flag
	RTS



; *****  Write Window Register  *****
; Program a windowing register via the SAPHIRA serial interface.
SET_WR	MOVE	Y:<XTAIL,A
	TST	A		; Check for zero
	JEQ	WR0
	DO	A,WR0
	MOVE	#<SER_0,R0	; bit = 0 (pixel disabled)
	CLOCK2
;	NOP
WR0

	MOVE	Y:<XBLK,A
	TST	A		; Check for zero
	JEQ	WR1
	DO	A,WR1
	MOVE	#<SER_1,R0	; bit = 1 (pixel enabled)
	CLOCK2
	NOP
WR1

	MOVE	Y:<XSTBLK,A
	TST	A		; Check for zero
	JEQ	WR2
	DO	A,WR2
	MOVE	#<SER_0,R0	; bit = 0 (pixel disabled)
	CLOCK2
	NOP
WR2

	MOVE	Y:<YTAIL,A
	TST	A		; Check for zero
	JEQ	WR3
	DO	A,WR3
	MOVE	#<SER_0,R0	; bit = 0 (pixel disabled)
	CLOCK2
	NOP
WR3

	MOVE	Y:<YRAS,A
	TST	A		; Check for zero
	JEQ	WR4
	DO	A,WR4
	MOVE	#<SER_1,R0	; bit = 1 (pixel enabled)
	CLOCK2
	NOP
WR4

	MOVE	Y:<YSTART,A
	TST	A		; Check for zero
	JEQ	WR5
	DO	A,WR5
	MOVE	#<SER_0,R0	; bit = 0 (pixel disabled)
	CLOCK2
	NOP
WR5

	RTS

; Always reset entire array (DEBUG)
WRRRST	MOVE	Y:<T_XSIZE,A
	REP	#4 	    ; REP #4 for 16
	ASR	A		; Divide by 8 for # blocks
	NOP			; Register access restriction
	DO	A,WR6
	MOVE	#<SER_1,R0	; bit = 1 (pixel enabled)
	CLOCK2
	NOP
WR6
	MOVE	Y:<T_YSIZE,A
	NOP			; Register access restriction
	DO	A,WR7
	MOVE	#<SER_1,R0	; bit = 1 (pixel enabled)
	CLOCK2
	NOP
WR7
	JMP	WR5

	
READ_CONTROLLER_CONFIGURATION
	MOVE	Y:<CONFIG,Y1		; Just transmit the configuration
	JMP		<FINISH1

SELECT_DUAL_TRANSMITTER
	JCLR	#0,X:(R3)+,SINGLE_XMTR
	BSET	#ST_XMT2,X:<STATUS
	JMP		<FINISH
SINGLE_XMTR
	BCLR	#ST_XMT2,X:<STATUS
	JMP		<FINISH

;  **********************    End of application    ************************


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
	DC	'RST',RST_ARRAY
	DC  'PON',POWER_ON		; Turn on all camera biases and clocks
	DC  'POF',POWER_OFF		; Turn +/- 15V power supplies off
	DC  'DON',START
	DC	'SET',SET_EXPOSURE_TIME
;	DC	'AEX',ABORT_EXPOSURE
;	DC	'ABR',ABORT_EXPOSURE
	DC	'RCC',READ_CONTROLLER_CONFIGURATION 
	DC  'STP',STP		; Exit continuous reset mode
	DC	'IDL',IDLE		; Enable continuous reset mode

; Continuous readout commands
;	DC	'SNF',SET_NUMBER_OF_FRAMES
;	DC	'FPB',SET_NUMBER_OF_FRAMES_PER_BUFFER

; Test the second fiber optic transmitter
;    DC	'XMT',SELECT_DUAL_TRANSMITTER

; More commands
	DC 	'LDP',LOAD_PARAMETERS
;	DC	'SSS',SET_SUBARRAY_SIZE
;	DC	'SSP',SET_SUBARRAY_POSITION
	DC	'CLR',CLR_ARRAY
	DC	'INI',INIT_SAPHIRA
;	DC	'APD',SET_APD_GAIN

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


; ***** Status values *****

T_SW_ID		DC	$001800	; Software version number (0.18)
T_INST_ID	DC	'SPH'	; Instrument ID (SAPHIRA)

T_STATUS	DC	0	; Status word
; Flag Bits
IDLING		EQU	0	; Idling
EXPING		EQU	1	; Exposing
RDCBUSY		EQU	2	; Read operation is busy.
RDING		EQU	3	; Reading array

T_ERROR		DC	0	; Error word
; Flag bits
BAD_MD		EQU	0	; Bad readout mode setting

T_XSIZE		DC	256	; Total number of pixels per row
T_YSIZE		DC	256	; Total number of pixels per column

ZERO DC	0
ERR_RPL DC	'ERR'		; Reply message: command unrecognised
CONFIG		DC	CC		; Controller configuration

; **** Video Board Parameters ****
VID0	EQU     $000000	; Video board # 0 (select = 0)
VID1	EQU     $100000 ; Video board # 1
XMIT_8	EQU		$00F1C0 ; one video board (8 channels)
XMIT_16	EQU		$00F3C0 ; two video boards (16 channels)

; Channel Offsets
VDACOA	EQU		$0E0000	; Video board DAC A
VDACOB	EQU		$0E4000	; Video board DAC B
VDACOC	EQU		$0E8000	; Video board DAC C
VDACOD	EQU		$0EC000	; Video board DAC D
VDACOE	EQU		$0F0000	; Video board DAC E
VDACOF	EQU		$0F4000	; Video board DAC F
VDACOG	EQU		$0F8000	; Video board DAC G
VDACOH	EQU		$0FC000	; Video board DAC H

; Video Biases Locations
VDACBA	EQU		$0C4000	; Video board bias A (pin 17)
VDACBB	EQU		$0C8000	; Video board bias B (pin 33)
VDACBC	EQU		$0CC000	; Video board bias C (pin 16)
VDACBD	EQU		$0D0000	; Video board bias D (pin 32, OFFSET)
VDACBE	EQU		$0D4000	; Video board bias E (pin 15)
VDACBF	EQU		$0D8000	; Video board bias F (pin 31, VCI)
VDACBG	EQU		$0DC000	; Video board bias G (pin 14, PRV)

; **** Clock Board Addresses ****
CLKDAC	EQU		$200000	; Clock driver boards DAC select = 2
CLKA	EQU     $002000 ; Select bottom of the first clock driver board
CLKB	EQU     $003000 ; Select top of the first clock driver board
BIASBD	EQU		$800000 ; ARC-45 bias board DACs

; ***** Readout parameters *****

; Parameters not changeable on-the-fly

T_EXP_TIM	DC	0	; Exposure time [ms]
T_NUM_RST	DC	1	; Number of reset frames
T_ADC_OS0	DC	$810	; A/D input offset voltage, ch0
T_ADC_OS1	DC	$000	; A/D input offset voltage, ch1 ; why $000 ? channel clearly offset from others in output images
T_ADC_OS2	DC	$810	; A/D input offset voltage, ch2
T_ADC_OS3	DC	$810	; A/D input offset voltage, ch3
T_ADC_OS4	DC	$810	; A/D input offset voltage, ch4 
T_ADC_OS5	DC	$810	; A/D input offset voltage, ch5
T_ADC_OS6	DC	$810	; A/D input offset voltage, ch6
T_ADC_OS7	DC	$810	; A/D input offset voltage, ch7

; Parameters changeable on-the-fly
; The following locations are an input buffer for readout parameters.
; Seperate copies of these values are kept internally.  

P_BUF		DC	ENDP_BUF-P_BUF-1	; Length of input buffer
						; (not a parameter)

T_PARMID	DC	1	; parameter set identifier

T_MODE		DC	$000000	; readout mode
; Bit definitions
SIMD		EQU	1	; (unused) Simulate data (data value = pixel #)
EXTREFSUB	EQU	7	; External reference frame subtraction
FPNFEN		EQU	3	; (unused) Fixed-pattern Noise Frame subtraction
GRABFIXD	EQU	4	; (unused) Capture Fixed-pattern Noise Frame
WINDOW		EQU	0	; (unused) Use detector window mode
FOWLER		EQU	5	; (unused) Fowler sampling (else SUTR)
PBP_RST		EQU	6	; (unused) Enable pixel-by-pixel reset

T_SAMPLES	DC	2 ; Samples per image (power of 2 for Fowler smp)
T_PXSAMP	DC	1	; Number of samples per pixel (power of 2)

T_XSUBAP	DC	1	; (unused) Number of subapertures in X direction
T_YSUBAP	DC	1	; (unused) Number of subapertures in Y direction
T_XSTART	DC	0	; Offset to first column of pixels to digitize (0 for full frame) index starts at 0 ; 47
T_YSTART	DC	0	; Offset to first row of pixels to digitize (0 for full frame)			    ; 99
T_XRAS		DC	256	; Number of X pixels per subaperture (320 for full frame)			    ; 96
T_YRAS		DC	256	; Number of Y pixels per subaperture (256 for full frame)			    ; 96
T_XSPACE	DC	0	; (unused) Number of pixels between subarrays
T_YSPACE	DC	0	; (unused) Number of lines between subarrays
T_NPIXEL	DC	65536	; Frame size (81920 for full frame) 96*96 = 9216				    ; 5120

;T_TRIGGER	DC	0	; Trigger tracker

ENDP_BUF

; *************************   Y Data (Internal)   *************************


; *****  Readout parameters  ***** 
; These are the in-use values of the on-the-fly parameters and should not be 
; changed directly with WRM. Instead, write the new values to the parameter 
; input buffer using WRM and then send an LDP.

; Input readout parameters
PARMID		DC	0	; Parameter set identifier

MODE		DC	$000000	; Readout mode
SAMPLES		DC	2	; Samples per image; Default: 1
PXSAMP		DC	1	; Samples per pixel

XSUBAP		DC	1	; (unused) Number of subapertures in X direction
YSUBAP		DC	1	; (unused) Number of subapertures in Y direction
XSTART		DC	0	; Offset to 1st column to digitize
YSTART		DC	0	; Offset to 1st row to digitize
XRAS		DC	256	; Number of X pixels per subaperture; Default: 320
YRAS		DC	256	; Number of Y lines per subaperture; Default: 256
XSPACE		DC	0	; (unused) Number of X pixels to skip between subaps
YSPACE		DC	0	; (unused) Number of Y lines to skip between subaps
NPIXEL		DC	65536	; Frame size; Default: 81920


; Calculated readout parameters
XBLK		DC	20	; # 16-pixel blocks in XRAS
XSTBLK		DC	0	; # 16-pixel blocks in XSTART
XTAIL		DC	0	; # 16-pixel blocks at end of row
YTAIL		DC	0	; # pixels at top of column
NPXCLR		DC	65536	; # entries to clear in image buffer
NPXSEND		DC	65536	; # pixels to process and transmit from internal buffer
NPCI_X		DC	8192	; "x" value for PCI interface counter
NPCI_Y		DC	8	; "y" value for PCI interface counter
NPLPX		DC  	0
IDLCKS		DC	8196	; # clocks for one frame in idle mode

; Readout constants
RSTCKS		DC	2	; # clocks for reset
;RSTCKS		DC	11	; DEBUG

TWENTY 		DC 	20

; *****  Flag Register  *****

FLAGREG		DC	0	; Miscellaneous flag register
; Bit definitions
DO_RST		EQU	0	; (unused) reset line before reading
XMTRAW		EQU	1	; transmit pixels directly (no co-add)
COADD		EQU	2	; (unused) enable co-adding of frame samples
ADDSUB		EQU	3	; (unused) add/subtract samples to/from buffer
FPNFSUB		EQU	4	; (unused) enable FPNF subraction
ABTEXP		EQU	5	; abort current exposure set
SHIFT		EQU	7	; (unused) set if sample averaging required
LDPFLG		EQU	8	; set if parameter load required
REFFRM		EQU	9	; set if reference frame
PXSMPS		EQU	10	; (unused) set if multiple pixel samples
MCR_SET		EQU	11	; set if setting MCR register
CMD_RCV		EQU	12	; set if command received


; ***** Clock waveforms *****
; SAPHIRA Array Clocking Information:
; NCS is active low and enables the serial interface.
; ARRCLK is used for readout (pixel output on xx edge) and serial data.
; MDIN is the data in signal for the serial interface.
; RESET is pulsed high to reset the array.
; FDEM (frame demand) is pulsed high to initiate frame readout.


; Clock board switch state bit definitions:

; Lower clocks (CLKA)
ARRCLK		EQU	$1
RESET		EQU	$2
NEXT_POR	EQU	$4
FDEM		EQU	$8
NCS		EQU	$10
MDIN		EQU	$20

; Upper clocks (CLKB)
VDD		EQU	$1+$8	; VDD is connected to two clock outputs
VDDPIX		EQU	$2
VDDA		EQU	$4
VDD_OP		EQU	$10
LED		EQU	$20

; Delay Constants
PIX_DLY		EQU	$0C0000	; PIXEL clock delay (12x40+40 = 520 ns)
RST_DLY		EQU	$200000	; PIXEL clock delay (32x40+40)
FDEMDLY		EQU	$200000	; FDEM delay (32x40+40) 
POR_DLY		EQU	$BE0000	; power on sequence delay (62x320+40 = 19.88 us)
DLY20US		EQU	$BE0000	; 20 us delay (62x320+40 = 19.88 us)
SER_DLY		EQU	$400000	; serial interface delay (16x40+40)

XFER		EQU	8	; Bit #3 = A/D data -> FIFO 	(high going edge)
X___		EQU	0
START_AD	EQU	0	; Bit #2 = A/D Convert 		(low going edge to start conversion)
S_______	EQU	4
RESET_INTG	EQU	0	; Bit #1 = Reset Integrator  	(=0 to reset)
R_________	EQU	2
ENABLE_INTG	EQU	0	; Bit #0 = Integrate 		(=0 to integrate)
E__________	EQU	1

; Clock the multiplexer, integrate the video signal, A/D convert and transmit
START_ADC
	DC	STOP_ADC-START_ADC-1					;
	DC	CLKA+0000000+ARRCLK+00000+NEXT_POR+0000+NCS+0000	; Array CLK high
	DC	VID0+$010000+X___+S_______+RESET_INTG+E__________	; Reset integrator 010000
	DC	VID0+$010000+X___+S_______+R_________+E__________	; Settling time 010000
	DC	VID0+$0A0000+X___+S_______+R_________+ENABLE_INTG	; Integrate
	DC	CLKA+$000000+000000+00000+NEXT_POR+0000+NCS+0000	; Array CLK low
	DC	VID0+$010000+X___+S_______+R_________+ENABLE_INTG	; Integrate
	DC	VID0+$0A0000+X___+START_AD+R_________+E__________	; Start A/D conversion
	DC	VID0+$000000+XFER+S_______+R_________+E__________	; A/D data--> FIFO
XMT_PXL	DC	XMIT_16							; Transmit pixels
STOP_ADC

START_MIMIC_ADC
	DC	STOP_MIMIC_ADC-START_MIMIC_ADC-1
	DC	CLKA+0000000+ARRCLK+00000+NEXT_POR+0000+NCS+0000	; Array CLK high
	DC	VID0+$010000+X___+S_______+R_________+E__________	; Reset integrator 010000
	DC	VID0+$010000+X___+S_______+R_________+E__________	; Settling time 010000
	DC	VID0+$0A0000+X___+S_______+R_________+E__________	; Integrate
	DC	CLKA+$000000+000000+00000+NEXT_POR+0000+NCS+0000	; Array CLK low	
	DC	VID0+$010000+X___+S_______+R_________+E__________	; Integrate
	DC	VID0+$0A0000+X___+S_______+R_________+E__________	; Start A/D conversion
	DC	VID0+$000000+X___+S_______+R_________+E__________	; A/D data--> FIFO
STOP_MIMIC_ADC

ROW_START	DC	CLKA+$810000+ARRCLK+00000+NEXT_POR+0000+NCS+0000	; 2*320 = 640 ns

; ARRCLK+RESET+NEXT_POR+FDEM+NCS+MDIN
; Start new frame (frame demand)
ST_FRM	DC	CLKA+FDEMDLY+000000+00000+NEXT_POR+FDEM+NCS+0000
	DC	CLKA+PIX_DLY+ARRCLK+00000+NEXT_POR+FDEM+NCS+0000
	
; Reset array
RST_ARR	DC	CLKA+PIX_DLY+000000+RESET+NEXT_POR+0000+NCS+0000
	
RST_PX	DC	CLKA+RST_DLY+ARRCLK+RESET+NEXT_POR+0000+NCS+0000
	DC	CLKA+RST_DLY+000000+RESET+NEXT_POR+0000+NCS+0000
	DC	CLKA+RST_DLY+000000+00000+NEXT_POR+0000+NCS+0000

; Pixel clock delays to keep clock cadence
;RD_DLY	DC	VID0+$0A0000	; reading (10x40+40 = 480 ns)
;IDL_DLY	DC	VID0+$0C0000	; idling (12x40+40 = 520 ns)
;RST_DLY	DC	VID0+$000000	; resetting (0x40+40 = 40 ns)
;EXP_DLY	DC	VID0+$0C0000	; exposing (12x40+40 = 520 ns)
;RD_DLY	DC	CLKA+$0A0000	; reading (10x40+40 = 480 ns)
;IDL_DLY	DC	CLKA+$0C0000	; idling (12x40+40 = 520 ns)
;RST_DLY	DC	CLKA+$000000	; resetting (0x40+40 = 40 ns)
;EXP_DLY	DC	CLKA+$0C0000	; exposing (12x40+40 = 520 ns)

;                            VDD+VDDPIX+VDDA+VDD_OP+LED
; Power on sequence
POR_0A	DC	CLKA+0000000
POR_0B	DC	CLKB+0000000
POR_1	DC	CLKB+POR_DLY+VDD+000000+0000+000000+000
POR_2	DC	CLKB+POR_DLY+VDD+VDDPIX+VDDA+VDD_OP+000
POR_3	DC	CLKA+POR_DLY+000000+00000+NEXT_POR+0000+NCS+0000


; Serial data "0"	
SER_0	DC	CLKA+SER_DLY+000000+00000+NEXT_POR+0000+000+0000
	DC	CLKA+SER_DLY+ARRCLK+00000+NEXT_POR+0000+000+0000

; Serial data "1"	
SER_1	DC	CLKA+SER_DLY+000000+00000+NEXT_POR+0000+000+MDIN
	DC	CLKA+SER_DLY+ARRCLK+00000+NEXT_POR+0000+000+MDIN

; End serial transmission sequence
END_SER	DC	CLKA+SER_DLY+000000+00000+NEXT_POR+0000+000+0000	
	DC	CLKA+SER_DLY+000000+00000+NEXT_POR+0000+NCS+0000


; *****  Clock voltage definitions  *****
; We have 8-bit DACs!!! Not 12-bits!
CLKHI	EQU	$D0	; DAC setting for 5 volts (HIA clock driver board)
CLKLO	EQU	$00	; D/A value on Clock Driver Board for 0 volts

; cold temp values of 5V
VDDHI	EQU	$E0	; VDD setting (5V) ; $D0 == 5V, $4F == 2V
VPXHI	EQU	$D0	; VDDPIX setting (5V)
VDAHI	EQU	$D0	; VDDA setting (5V)
VOPHI	EQU	$C0	; VDD_OP setting (5V)

LEDHI	EQU	$FF	; LED drive setting (6.0V)

; Clock driver board initial DAC settings
CLKDACS	DC 	END_CD-CLKDACS-1

	DC	$2A0080				; DAC = unbuffered mode
	; Clocks
	DC $200100+CLKHI			; ARRCLK High   (Pin #1)
	DC $200200+CLKLO			; ARRCLK Low
	DC $200400+CLKHI			; ARRAY_RESET High  (Pin #2)
	DC $200800+CLKLO			; ARRAY_RESET Low
	DC $202000+CLKHI			; NEXT_POR High  (Pin #3)
	DC $204000+CLKLO			; NEXT_POR Low
	DC $208000+CLKHI			; FDEM High  (Pin #4)
	DC $210000+CLKLO			; FDEM Low
	DC $220100+CLKHI			; NCS High  (Pin #5)
	DC $220200+CLKLO			; NCS Low
	DC $220400+CLKHI			; MDIN High  (Pin #6)
	DC $220800+CLKLO			; MDIN Low
	
	; Digital Biases
	DC $260100+VDDHI			; VDD High (Pin #13)
	DC $260200+CLKLO			; VDD Low		
	DC $260400+VPXHI			; VDDPIX High (Pin #14)
	DC $260800+CLKLO			; VDDPIX Low
	DC $262000+VDAHI			; VDDA High  (Pin #15)
	DC $264000+CLKLO			; VDDA Low
	DC $268000+VDDHI			; VDD High  (Pin #16)
	DC $270000+CLKLO			; VDD Low
	DC $280100+VOPHI			; VDD_OP High  (Pin #17)
	DC $280200+CLKLO			; VDD_OP Low
	DC $280400+LEDHI			; LED High
	DC $280800+CLKLO			; LED Low

END_CD

COMMON	EQU	 0.0	; COMMON V = 3.4 - COMMON (+2.5V setting) ; -0.9 Vbias == 2V, -1.9 Vbias == 3V.. -12.9 Vbias == 14 V
RAMP	EQU	 +1.0	; Volts per second ramp rate. This doesn't really matter

; *****  Bias Voltages  *****
; Both bias DACs on the video processor board are set for bipolar operation 
; ($000 = -5.0V, $FFF = +5.0V).

VOFFSET  EQU $5e0       ; $4C0 for ROIC  
VOFFSET1 EQU VOFFSET	; typically $610 ~ -1.45 V
VOFFSET2 EQU VOFFSET	; to test video inputs, COMMON and PRV, use $550
VOFFSET3 EQU VOFFSET	; use $800 or $810 for ME911 ROIC
VOFFSET4 EQU VOFFSET	; use $610 for SAPHIRA
VOFFSET5 EQU VOFFSET
VOFFSET6 EQU VOFFSET
VOFFSET7 EQU VOFFSET
VOFFSET8 EQU VOFFSET    ; video board #0 (1 through 8)
VOFFSETA EQU VOFFSET    ; video board #1 (A through H)	
VOFFSETB EQU VOFFSET	
VOFFSETC EQU VOFFSET
VOFFSETD EQU VOFFSET
VOFFSETE EQU VOFFSET
VOFFSETF EQU VOFFSET
VOFFSETG EQU VOFFSET
VOFFSETH EQU VOFFSET

DC_BIASES	DC	END_DCB-DC_BIASES-1

; Integrator gain and FIFO reset
	DC	VID0+$0c3000			; Integrate, R = 1k, High gain, Fast
	DC	VID0+$0c1000			; Reset image data FIFOs
	DC	VID0+$0c2000			; High 16 A/D bits to backplane (hardware default)
	DC	VID0+$0c2002			; WARP Off
	DC  	VID1+$0c3000			; video board #1 (same settings as above)
	DC	VID1+$0c1000
	DC	VID1+$0c2000
	DC	VID1+$0c2002

; Range of DACs on Video boards is +/- 5V for FFTCam board (but jumpered to clip negative voltages to -0.5V)
PRV		DC	VID0+VDACBG+$FC0	; pixel reset voltage (P2 #1, 4.5V); typically $F33 for 4.5V
VCI		DC	VID0+VDACBF+$D99	; voltage clamp input (P2 #2, 3.5V); typically $D99 for 3.5
OFFSET		DC	VID0+VDACBD+$800	; preamp offset (P2 #4, 0.0V); typically $80F for 0.0V

	; Video board offsets
	DC	VID0+$0e0000+VOFFSET1		; Output #0, video board #0
	DC	VID0+$0e4000+VOFFSET2		; Output #1
	DC	VID0+$0e8000+VOFFSET3		; Output #2
	DC	VID0+$0ec000+VOFFSET4		; Output #3
	DC	VID0+$0f0000+VOFFSET5		; Output #4
	DC	VID0+$0f4000+VOFFSET6		; Output #5
	DC	VID0+$0f8000+VOFFSET7		; Output #6
	DC	VID0+$0fc000+VOFFSET8		; Output #7
	DC	VID1+$0e0000+VOFFSETA		; Output #0, video board #1
	DC	VID1+$0e4000+VOFFSETB		; Output #1
	DC	VID1+$0e8000+VOFFSETC		; Output #2
	DC	VID1+$0ec000+VOFFSETD		; Output #3
	DC	VID1+$0f0000+VOFFSETE		; Output #4
	DC	VID1+$0f4000+VOFFSETF		; Output #5
	DC	VID1+$0f8000+VOFFSETG		; Output #6
	DC	VID1+$0fc000+VOFFSETH		; Output #7
END_DCB

;set Avalanche bias
AV_BIASES DC END_AVB-AV_BIASES-1
	DC	BIASBD+$0e0000+@CVI(((COMMON+10.0)/20.0)*4095)	; pin #10
END_AVB

ZERO_BIASES
	DC END_ZERO_BIASES-ZERO_BIASES-1
PRVOFF		DC	VID0+VDACBG+$800	; pixel reset voltage (P2 #1, 0V)
VCIOFF		DC	VID0+VDACBF+$800	; voltage clamp input (P2 #2, 0V)
OFFSETOFF	DC	VID0+VDACBD+$800	; preamp offset (P2 #4, 0.0V)
		DC 	BIASBD+$0e0000+@CVI(((10.0)/20.0)*4095) ; AV bias pin #10
END_ZERO_BIASES

; DAC addresses for A/D input offset voltages
ADC_OS0		DC	VID0+VDACOA	; channel A
ADC_OS1		DC	VID0+VDACOB	; channel B
ADC_OS2		DC	VID0+VDACOC	; channel C
ADC_OS3		DC	VID0+VDACOD	; channel D
ADC_OS4		DC	VID0+VDACOE	; channel E
ADC_OS5		DC	VID0+VDACOF	; channel F
ADC_OS6		DC	VID0+VDACOG	; channel G
ADC_OS7		DC	VID0+VDACOH	; channel H

; *****  SAPHIRA internal register settings  *****
DCR_REG		DC	%00000000		; Detector control register
MCR_REG		DC	%10001110		; Multiplexer control register

; DCR bit defintions
MCRBIT		EQU	4
WDRBIT		EQU	5
WRRBIT		EQU	6

; *****  Miscellaneous internal data  *****

RSTCNT		DC	1	; Reset frame counter
DEBUG0		DC	$CCD	; debugging variable
DEBUG1		DC	$CCD	; debugging variable
DEBUG2		DC	0	; debugging variable
DEBUG3		DC	0	; debugging variable
FOUR		DC	4

; Commands
IIA_HDR		DC	$020102	; Initialize Image Array (to PCI board)
IIA_CMD		DC	'IIA'	; Initialize Image Array (to PCI board)
RDA_HDR		DC	$020104	; ReaD Array (to PCI board)
RDA_CMD		DC	'RDA'	; ReaD Array (to PCI board)

; Replies
POE_RPL		DC	'POE'	; Power on error

; Delays for analog power supplies to settle (10us increments)
LV_WAIT		DC	20000	; Delay for low voltage (+/-16V, +/-6V) supplies
HV_WAIT		DC	60000	; Delay for high voltage (+36V) supply

; Timing board latch initial state
LTC_INI		DC	$78	; CDAC = 0, Clear DACs
				; DUALCLK = 0, Separate clock board halves
				; ENCK = 0, Disable clock and DAC outputs
				; ONE_ADC = 1, One-ADC-at-a-time mode

END_APPLICATON_Y_MEMORY	EQU	@LCV(L)

;  End of program
	END
