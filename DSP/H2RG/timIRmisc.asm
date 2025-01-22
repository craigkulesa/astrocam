; Clear all video processor analog switches to lower their power dissipation

POWER_OFF
	JSR	<CLEAR_SWITCHES_AND_DACS	; Clear switches and DACs
	BSET	#LVEN,X:HDR
	BSET	#HVEN,X:HDR
	JMP	<FINISH

; Execute the power-on cycle, as a command
POWER_ON
	JSR	<CLEAR_SWITCHES_AND_DACS	; Clear switches and DACs
	
; Turn on the low voltages (+/- 6.5V, +/- 16.5V) and then delay awhile
	BCLR	#LVEN,X:HDR		; Turn on the low voltage power 
	MOVE	#>100,A
	JSR	<MILLISEC_DELAY		; Wait one hundred milliseconds
	JCLR	#PWROK,X:HDR,PWR_ERR	; Test if the power turned on properly
	JSR	<SET_BIASES		; Turn on the DC bias supplies
	MOVE	#CONT_RST,R0		; --> continuous readout state
	MOVE	R0,X:<IDL_ADR
	BSET	#ST_DIRTY,X:<STATUS
	MOVE	#RST_INTERNAL_REGISTERS,R0 ; Clear the H2RG internal registers
	JSR	<CLOCK
	JSR	<INIT_H2RG		; Initialize the H2RG array  
	JMP	<FINISH

; The power failed to turn on because of an error on the power control board
PWR_ERR	BSET	#LVEN,X:HDR		; Turn off the low voltage emable line
	BSET	#HVEN,X:HDR		; Turn off the high voltage emable line
	JMP	<ERROR

; Set all the DC bias voltages and video processor offset values, 
;   reading them from the 'DACS' table
SET_BIASES
	BSET	#3,X:PCRD		; Turn on the serial clock
	BCLR	#1,X:<LATCH		; Separate updates of clock driver
	BSET	#CDAC,X:<LATCH		; Disable clearing of DACs
	BCLR	#ENCK,X:<LATCH		; Disable clock and DAC output switches
	MOVEP	X:LATCH,Y:WRLATCH	; Write it to the hardware
	JSR	<PAL_DLY		; Delay for all this to happen

; Specialized turn-on sequence for H2RG
	MOVE	#<ZERO_BIASES,R0	; Zero out all the DC bias DACs
	JSR	<WR_TABLE
	MOVE	#>3,A
	JSR	<MILLISEC_DELAY		; Wait three milliseconds
	BSET	#ENCK,X:<LATCH		; Enable clock and DAC output switches
	MOVEP	X:LATCH,Y:WRLATCH	; Write it to the hardware

	MOVE	#DC_BIASES,R0		; Write to the DC bias DACS
	JSR	<WR_TABLE
	MOVE	#>10,A
	JSR	<MILLISEC_DELAY		; Wait ten milliseconds	
	MOVE	#<DACS,R0		; Write to the clock driver DACs
	JSR	<WR_TABLE
	MOVE	#>10,A
	JSR	<MILLISEC_DELAY		; Wait ten milliseconds

	BCLR	#3,X:PCRD		; Turn the serial clock off
	RTS

WR_TABLE
	DO	Y:(R0)+,L_DAC0
	MOVE	Y:(R0)+,A
	JSR	<XMIT_A_WORD
	NOP
L_DAC0
	RTS

SET_BIAS_VOLTAGES
	JSR	<SET_BIASES
	JMP	<FINISH

CLR_SWS	JSR	<CLEAR_SWITCHES_AND_DACS	; Clear switches and DACs
	JMP	<FINISH

CLEAR_SWITCHES_AND_DACS
	BCLR	#CDAC,X:<LATCH		; Clear all the DACs
	BCLR	#ENCK,X:<LATCH		; Disable all the output switches
	MOVEP	X:LATCH,Y:WRLATCH	; Write it to the hardware
	BSET	#3,X:PCRD		; Turn the serial clock on
	JSR	<PAL_DLY
	MOVE	#<ZERO_BIASES,R0
	JSR	<WR_TABLE
	MOVE	#GAIN,A		; Video processor gain, x1 or x4
	CLR	B
	MOVE	#$100000,X0	; Increment over board numbers for DAC writes
	MOVE	#$001000,X1	; Increment over board numbers for WRSS writes
	DO	#8,L_VIDEO	; Eight video processor boards maximum
	JSR	<XMIT_A_WORD	; Transmit A to TIM-A-STD
	ADD	X0,A
	MOVE	B,Y:WRSS
	JSR	<PAL_DLY	; Delay for the serial data transmission
	ADD	X1,B
L_VIDEO	
	BCLR	#3,X:PCRD		; Turn the serial clock off
	RTS

; Start the exposure timer and monitor its progress
EXPOSE	MOVEP	#0,X:TLR0		; Load 0 into counter timer
	MOVE	#0,X0
	MOVE	X0,X:<ELAPSED_TIME	; Set elapsed exposure time to zero
	MOVE	X:<EXPOSURE_TIME,B
	TST	B			; Special test for zero exposure time
	JEQ	<END_EXP		; Don't even start an exposure
	SUB	#1,B			; Timer counts from X:TCPR0+1 to zero
	BSET	#TIM_BIT,X:TCSR0	; Enable the timer #0
	MOVE	B,X:TCPR0
CHK_RCV	MOVE	#<COM_BUF,R3		; The beginning of the command buffer
	JSR	<GET_RCV		; Check for an incoming command
	JCS	<PRC_RCV		; If command is received, go check it
CHK_TIM	JCLR	#TCF,X:TCSR0,CHK_RCV	; Wait for timer to equal compare value
END_EXP	BCLR	#TIM_BIT,X:TCSR0	; Disable the timer
	JMP	(R7)			; This contains the return address

; Start the exposure and initiate FPA readout
START_EXPOSURE

; Setup windowing or whole image readout mode if needed
	JSSET	#ST_DIRTY,X:STATUS,SETUP_READ_MODE
	MOVE	#TST_RCV,R0		; Process commands, don't idle 
	MOVE	R0,X:<IDL_ADR		;    during the exposure

; Test for continuous readout
	MOVE	Y:<N_FRAMES,A
	CMP	#1,A
	JLE	<INIT_PCI_BOARD
	
INIT_FRAME_COUNT
	JSR	<WAIT_TO_FINISH_CLOCKING	
	MOVE	#$020102,B		; Initialize the PCI frame counter
	JSR	<XMT_WRD
	MOVE	#'IFC',B
	JSR	<XMT_WRD
	MOVE	#0,X0
	MOVE	X0,Y:<I_FRAME		; Initialize the frame number
	JMP	<INIT_PCI_BOARD
	
; Start up the next frame of the coaddition series
NEXT_FRAME
	MOVE	Y:<I_FRAME,A		; Get the # of frames coadded so far
	ADD	#1,A
	MOVE	Y:<N_FRAMES,X0		; See if we've coadded enough frames
	MOVE	A1,Y:<I_FRAME		; Increment the coaddition frame counter
	CMP	X0,A
	JGE	<RDA_END		; End of coaddition sequence

	MOVE	Y:<IBUFFER,A		; Get the position in the buffer
	ADD	#1,A
	MOVE	Y:<N_FPB,X0
	MOVE	A1,Y:<IBUFFER
	CMP	X0,A
	JLT	<RST_AR			; Test if the frame buffer is full

INIT_PCI_BOARD
	MOVE	#0,X0
	MOVE	X0,Y:<IBUFFER		; IBUFFER counts from 0 to N_FPB
	MOVE	#$020102,B
	JSR	<XMT_WRD
	MOVE	#'IIA',B		; Initialize the PCI image address
	JSR	<XMT_WRD

; Clear the FPA if needed, and expose
RST_AR	JSSET	#ST_RST_MODE,X:STATUS,RESET_ARRAY 	; Reset array if needed
	JCLR	#ST_CDS,X:STATUS,NO_CDS
	JSR	<RD_ARRAY

NO_CDS	MOVE	#L_SEX1,R7		; Return address at end of exposure
	JSR	<WAIT_TO_FINISH_CLOCKING
	JMP	<EXPOSE			; Delay for specified exposure time
L_SEX1
	JSR	<RD_ARRAY		; Finally, go read out the FPA
	JMP	<START

; Set the desired exposure time
SET_EXPOSURE_TIME
	MOVE	X:(R3)+,Y0
	MOVE	Y0,X:EXPOSURE_TIME
	JCLR	#TIM_BIT,X:TCSR0,FINISH	; Return if exposure not occurring
	MOVE	Y0,X:TCPR0		; Update timer if exposure in progress
	JMP	<FINISH

; Read the time remaining until the exposure ends
READ_EXPOSURE_TIME
	JSET	#TIM_BIT,X:TCSR0,RD_TIM	; Read DSP timer if its running
	MOVE	X:<ELAPSED_TIME,Y1
	JMP	<FINISH1
RD_TIM	MOVE	X:TCR0,Y1		; Read elapsed exposure time
	JMP	<FINISH1

; Pause the exposure - just stop the timer
PAUSE_EXPOSURE
	MOVEP	X:TCR0,X:ELAPSED_TIME	; Save the elapsed exposure time
	BCLR    #TIM_BIT,X:TCSR0	; Disable the DSP exposure timer
	JMP	<FINISH

; Resume the exposure - restart the timer
RESUME_EXPOSURE
	MOVEP	X:ELAPSED_TIME,X:TLR0	; Restore elapsed exposure time
	BSET	#TIM_BIT,X:TCSR0	; Re-enable the DSP exposure timer
	JMP	<FINISH

; Enable continuous readout mode
IDLE	MOVE	#CONT_RST,R0
	MOVE	R0,X:<IDL_ADR
	JMP	<FINISH

; Exit continuous readout mode
STP	MOVE	#TST_RCV,R0
	MOVE	R0,X:<IDL_ADR
	JMP	<FINISH

; Abort exposure - stop the timer and resume continuous readout mode
ABORT_EXPOSURE
	BCLR    #TIM_BIT,X:TCSR0	; Disable the DSP exposure timer
	JSR	<RDA_END
	JMP	<START

; Delay by by the number of milliseconds in Accumulator A1
MILLISEC_DELAY
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

; Generate a synthetic image by simply incrementing the pixel counts
SYNTHETIC_IMAGE
	CLR	A
	DO      Y:<NROWS,LPR_TST      	; Loop over each line readout
	DO      Y:<NCOLS,LSR_TST	; Loop over number of pixels per line
	REP	#20			; #20 => 1.0 microsec per pixel
	NOP
	ADD	#1,A			; Pixel data = Pixel data + 1
	NOP
	MOVE	A,B
	JSR	<XMT_PIX		;  transmit them
	NOP
LSR_TST	
	NOP
LPR_TST	
        JSR     <RDA_END		; Normal exit
	JMP	<START

; Transmit the 16-bit pixel datum in B1 to the host computer
XMT_PIX	ASL	#16,B,B
	NOP
	MOVE	B2,X1
	ASL	#8,B,B
	NOP
	MOVE	B2,X0
	NOP
	MOVEP	X1,Y:WRFO
	MOVEP	X0,Y:WRFO
	RTS

; Test the hardware to read A/D values directly into the DSP instead
;   of using the SXMIT option, A/Ds #2 and 3.
READ_AD	MOVE	X:(RDAD+2),B
	ASL	#16,B,B
	NOP
	MOVE	B2,X1
	ASL	#8,B,B
	NOP
	MOVE	B2,X0
	NOP
	MOVEP	X1,Y:WRFO
	MOVEP	X0,Y:WRFO
	REP	#10
	NOP
	MOVE	X:(RDAD+3),B
	ASL	#16,B,B
	NOP
	MOVE	B2,X1
	ASL	#8,B,B
	NOP
	MOVE	B2,X0
	NOP
	MOVEP	X1,Y:WRFO
	MOVEP	X0,Y:WRFO
	REP	#10
	NOP
	RTS

; Alert the PCI interface board that images are coming soon
PCI_READ_IMAGE
	MOVE	#$020104,B		; Send header word to the FO transmitter
	JSR	<XMT_WRD
	MOVE	#'RDA',B
	JSR	<XMT_WRD
	MOVE	Y:<NCOLS,B		; Number of columns to read
	JSR	<XMT_WRD
	MOVE	Y:<NROWS,B		; Number of rows to read
	JCLR	#ST_CDS,X:<STATUS,NO_CDS1
	LSR	B
NO_CDS1	JSR	<XMT_WRD
	RTS

; Wait for the clocking to be complete before proceeding
WAIT_TO_FINISH_CLOCKING
	JSET	#SSFEF,X:PDRD,*		; Wait for the SS FIFO to be empty	
	RTS

; This MOVEP instruction executes in 30 nanosec, 20 nanosec for the MOVEP,
;   and 10 nanosec for the wait state that is required for SRAM writes and 
;   FIFO setup times. It looks reliable, so will be used for now.

; Core subroutine for clocking out FPA charge
CLOCK	JCLR	#SSFHF,X:HDR,*		; Only write to FIFO if < half full
	NOP
	JCLR	#SSFHF,X:HDR,CLOCK	; Guard against metastability
	MOVE    Y:(R0)+,X0      	; # of waveform entries 
	DO      X0,CLK1                 ; Repeat X0 times
	MOVEP	Y:(R0)+,Y:WRSS		; 30 nsec Write the waveform to the SS 	
CLK1
	NOP
	RTS                     	; Return from subroutine

; Delay for serial writes to the PALs and DACs by 8 microsec
PAL_DLY	DO	#800,DLY	 ; Wait 8 usec for serial data transmission
	NOP
DLY	NOP
	RTS

; Write a number to an analog board over the serial link
WR_BIAS	BSET	#3,X:PCRD	; Turn on the serial clock
	JSR	<PAL_DLY
	JSR	<XMIT_A_WORD	; Transmit it to TIM-A-STD
	JSR	<PAL_DLY
	BCLR	#3,X:PCRD	; Turn off the serial clock
	JSR	<PAL_DLY
	RTS

; Let the host computer read the controller configuration
READ_CONTROLLER_CONFIGURATION
	MOVE	Y:<CONFIG,Y1		; Just transmit the configuration
	JMP	<FINISH1

; Set a particular DAC numbers, for setting DC bias voltages on the ARC32
;   clock driver and ARC46 IR video processor
;
; SBN  #BOARD  #DAC  ['CLK' or 'VID'] voltage
;
;				#BOARD is from 0 to 15
;				#DAC number
;				#voltage is from 0 to 4095

SET_BIAS_NUMBER			; Set bias number
	BSET	#3,X:PCRD	; Turn on the serial clock
	MOVE	X:(R3)+,A	; First argument is board number, 0 to 15
	REP	#20
	LSL	A
	NOP
	MOVE	A,X1		; Save the board number
	MOVE	X:(R3)+,A	; Second argument is DAC number
	MOVE	X:(R3)+,B	; Third argument is 'VID' or 'CLK' string
	CMP	#'VID',B
	JEQ	<VID_SET
	CMP	#'CLK',B
	JNE	<ERR_SBN

; For ARC32 do some trickiness to set the chip select and address bits
	MOVE	A1,B
	REP	#14
	LSL	A
	MOVE	#$0E0000,X0
	AND	X0,A
	MOVE	#>7,X0
	AND	X0,B		; Get 3 least significant bits of clock #
	CMP	#0,B
	JNE	<CLK_1
	BSET	#8,A
	JMP	<BD_SET
CLK_1	CMP	#1,B
	JNE	<CLK_2
	BSET	#9,A
	JMP	<BD_SET
CLK_2	CMP	#2,B
	JNE	<CLK_3
	BSET	#10,A
	JMP	<BD_SET
CLK_3	CMP	#3,B
	JNE	<CLK_4
	BSET	#11,A
	JMP	<BD_SET
CLK_4	CMP	#4,B
	JNE	<CLK_5
	BSET	#13,A
	JMP	<BD_SET
CLK_5	CMP	#5,B
	JNE	<CLK_6
	BSET	#14,A
	JMP	<BD_SET
CLK_6	CMP	#6,B
	JNE	<CLK_7
	BSET	#15,A
	JMP	<BD_SET
CLK_7	CMP	#7,B
	JNE	<BD_SET
	BSET	#16,A

BD_SET	OR	X1,A		; Add on the board number
	NOP
	MOVE	A,X0
	MOVE	X:(R3)+,A	; Fourth argument is voltage value, 0 to $fff
	LSR	#4,A		; Convert 12 bits to 8 bits for ARC32
	MOVE	#>$FF,Y0	; Mask off just 8 bits
	AND	Y0,A
	OR	X0,A
	JSR	<XMIT_A_WORD	; Transmit A to TIM-A-STD
	JSR	<PAL_DLY	; Wait for the number to be sent
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<FINISH
ERR_SBN	MOVE	X:(R3)+,A	; Read and discard the fourth argument
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<ERROR

; The command is for the DC biases on the ARC-46 video board
VID_SET	LSL	#14,A		; Put the DAC number 0-7 into bits 16-14
	NOP
	BSET	#19,A1		; Set bits to mean video processor DAC
	NOP
	BSET	#18,A1
	MOVE	X:(R3)+,X0	; Fourth argument is voltage value for ARC46,
	OR	X0,A		;  12 bits, bits 11-0
	OR	X1,A		; Add on the board number, bits 23-20
	NOP
	MOVE	A1,Y:0		; Save the DAC number for a little while
	JSR	<XMIT_A_WORD	; Transmit A to TIM-A-STD
	JSR	<PAL_DLY	; Wait for the number to be sent
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<FINISH

; Set the ARC-46 video board video offsets - 
;
;	SVO  #BOARD  #DAC  number

SET_VIDEO_OFFSET
	BSET	#3,X:PCRD	; Turn on the serial clock
	JSR	<PAL_DLY	; Let the serial transmitter get started
	MOVE	X:(R3)+,A	; First argument is board number, 0 to 15
	LSL	#20,A
	NOP
	MOVE	A,X1		; Board number, bits 23-20
	MOVE	X:(R3)+,A	; Second argument is DAC number
	LSL	#14,A		; Put the DAC number 0-7 into bits 16-14
	NOP
	OR	X1,A		; Add on the board number, bits 23-20
	NOP
	OR	#$0E0000,A	; Set bits 19-17 to mean video offset DAC
	MOVE	X:(R3)+,X0	; Third argument is voltage value for ARC46,
	OR	X0,A		;  12 bits, bits 11-0
	NOP
	MOVE	A1,Y:0		; Save the DAC number for a little while
	JSR	<XMIT_A_WORD	; Transmit A to TIM-A-STD
	JSR	<PAL_DLY	; Wait for the number to be sent
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<FINISH	

; Specify the MUX value to be output on the clock driver board
; Command syntax is  SMX  #clock_driver_board #MUX1 #MUX2
;				#clock_driver_board from 0 to 15
;				#MUX1, #MUX2 from 0 to 23

SET_MUX	BSET	#3,X:PCRD	; Turn on the serial clock
	MOVE	X:(R3)+,A	; Clock driver board number
	LSL	#20,A
	MOVE	#$003000,X0	; Bits to select MUX on ARC32 board
	OR	X0,A
	NOP
	MOVE	A1,X1		; Move here for later use
	
; Get the first MUX number
	MOVE	X:(R3)+,A	; Get the first MUX number
	TST	A
	JLT	<ERR_SM1
	MOVE	#>24,X0		; Check for argument less than 32
	CMP	X0,A
	JGE	<ERR_SM1
	MOVE	A,B
	MOVE	#>7,X0
	AND	X0,B
	MOVE	#>$18,X0
	AND	X0,A
	JNE	<SMX_1		; Test for 0 <= MUX number <= 7
	BSET	#3,B1
	JMP	<SMX_A
SMX_1	MOVE	#>$08,X0
	CMP	X0,A		; Test for 8 <= MUX number <= 15
	JNE	<SMX_2
	BSET	#4,B1
	JMP	<SMX_A
SMX_2	MOVE	#>$10,X0
	CMP	X0,A		; Test for 16 <= MUX number <= 23
	JNE	<ERR_SM1
	BSET	#5,B1
SMX_A	OR	X1,B1		; Add prefix to MUX numbers
	NOP
	MOVE	B1,Y1

; Add on the second MUX number
	MOVE	X:(R3)+,A	; Get the next MUX number
	TST	A
	JLT	<ERR_SM2
	MOVE	#>24,X0		; Check for argument less than 32
	CMP	X0,A
	JGE	<ERR_SM2
	REP	#6
	LSL	A
	NOP
	MOVE	A,B
	MOVE	#$1C0,X0
	AND	X0,B
	MOVE	#>$600,X0
	AND	X0,A
	JNE	<SMX_3		; Test for 0 <= MUX number <= 7
	BSET	#9,B1
	JMP	<SMX_B
SMX_3	MOVE	#>$200,X0
	CMP	X0,A		; Test for 8 <= MUX number <= 15
	JNE	<SMX_4
	BSET	#10,B1
	JMP	<SMX_B
SMX_4	MOVE	#>$400,X0
	CMP	X0,A		; Test for 16 <= MUX number <= 23
	JNE	<ERR_SM2
	BSET	#11,B1
SMX_B	ADD	Y1,B		; Add prefix to MUX numbers
	NOP
	MOVE	B1,A
	AND	#$F01FFF,A	; Just to be sure
	JSR	<XMIT_A_WORD	; Transmit A to TIM-A-STD
	JSR	<PAL_DLY	; Delay for all this to happen
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<FINISH
ERR_SM1	MOVE	X:(R3)+,A	; Throw off the last argument
ERR_SM2	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<ERROR

;***********  Special H2RG commands *******************

; This should clear the array when the 'Clear Array' button in the 
;   main Voodoo window is pressed.
CLR_ARRAY
	JSR	<RESET_ARRAY
	JMP	<FINISH

; Transmit a serial register command to the H2RG array
SER_COM	MOVE	#CSB_LOW,R0		; Enable one serial command link
	JSR	<CLOCK
NEXT	DO	#16,L_SERCOM		; The commands are 16 bits long
	JSET	#15,A1,B_SET		; Check if the bit is set or cleared
	MOVE	#CLOCK_SERIAL_ZERO,R0	; Transmit a zero bit
	JSR	<CLOCK
	JMP	<NEXTBIT
B_SET	MOVE	#CLOCK_SERIAL_ONE,R0	; Transmit a one bit
	JSR	<CLOCK
NEXTBIT	LSL	A			; Get the next most significant bit
	NOP	
L_SERCOM
	MOVE	#CSB_HIGH,R0		; Disable the serial command link
	JSR	<CLOCK
	RTS

SERIAL_COMMAND
	MOVE	X:(R3)+,A		; Get the command
	JSR	<SER_COM		; Send it to the serial command register
	JMP	<FINISH

; Assert MAINRESETB to clear all internal registers to default settings
RESET_INTERNAL_REGISTERS
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE	#RST_INTERNAL_REGISTERS,R0
	JSR	<CLOCK
	JMP	<FINISH

; Initialize the internal registers to default settings
INIT_H2RG
	BSET	#ST_DIRTY,X:<STATUS
	MOVE	#(OUTPUT_MODE_REGISTER+$2),A	; 4-output mode, use pin #7
	JSR	<SER_COM			;  for window output
	MOVE	#(OUTPUT_BUF_REG+$11),A		; Slow buffered readout mode
	JSR	<SER_COM			;  Unused outputs in high ohmic states
	MOVE	#(NORMAL_MODE_REG+$83),A	; Enhanced clocking, global reset 
	JSR	<SER_COM
	MOVE	#(WINDOW_MODE_REG+$83),A	; Windowing mode is enhanced
	JSR	<SER_COM			;  clocking, global reset
	RTS

INITIALIZE_H2RG
	JSR	<INIT_H2RG
	JMP	<FINISH

; Specify subarray readout size
SET_SUBARRAY_SIZE
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	BCLR	#ST_SA,X:<STATUS
	MOVE    X:(R3)+,X0		; Not used
	MOVE    X:(R3)+,A		; Whole array mode if ncols = 0 
	TST	A
	JEQ	<FINISH
	BSET	#ST_SA,X:<STATUS
	MOVE	A1,Y:<SA_NCOLS		; Number of columns in subimage read
	MOVE    X:(R3)+,X0
	MOVE	X0,Y:<SA_NROWS		; Number of rows in subimage read	
	JMP	<FINISH

; Specify subarray readout position
SET_SUBARRAY_POSITION
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE	X:(R3)+,X0
	MOVE	X0,Y:<SA_STARTROW	; Number of rows skip over
	MOVE	X:(R3)+,X0
	MOVE	X0,Y:<SA_BEGCOL		; Number of columns to skip over
	MOVE	X:(R3)+,X0		; Not used
	JMP	<FINISH

; Specify the delay time between clocking a row and beginning to read
SET_READ_DELAY
	MOVE	X:(R3)+,X0
	MOVE	X0,Y:<READ_DELAY
	JMP	<FINISH

SETUP_READ_MODE_FINISH
	JSR	<SETUP_READ_MODE
	JMP	<FINISH

; Set up for subarray, windowing and number of readout channels
SETUP_READ_MODE
	BCLR	#ST_DIRTY,X:<STATUS
	JCLR	#ST_SA,X:STATUS,WHOLE_FRAME
	JCLR	#ST_WM,X:STATUS,NOT_WM

; Set up for native H2RG windowing readout mode through one channel
	MOVE	Y:<SA_NCOLS,X0
	MOVE	X0,Y:<NCOLS_CLOCK
	MOVE	Y:<SA_NROWS,A
	JCLR	#ST_CDS,X:STATUS,NO_CDS4
	LSR	A
	NOP
NO_CDS4	MOVE	A1,Y:<NROWS_CLOCK
	MOVE	#XMIT_1,X0		; Only one channel transmits in
	MOVE	X0,Y:XMT_PXL		;   windowing mode
	MOVE	#>1,X0
	MOVE	X0,Y:<NCHS

	MOVE	Y:<SA_BEGCOL,A
	MOVE	#HORIZ_START_REG,X0	; Address of HorizStartReg
	ADD	X0,A
	JSR	<SER_COM

	MOVE	Y:<SA_NCOLS,X0
	MOVE	Y:<SA_BEGCOL,A
	ADD	X0,A
	MOVE	#HORIZ_STOP_REG,X0	; Address of HorizStopReg
	ADD	X0,A
	JSR	<SER_COM

	MOVE	Y:<SA_STARTROW,A
	MOVE	#VERT_START_REG,X0	; Address of VertStartReg
	ADD	X0,A
	JSR	<SER_COM

	MOVE	Y:<SA_NROWS,X0
	MOVE	Y:<SA_STARTROW,A
	ADD	X0,A
	MOVE	#VERT_STOP_REG,X0	; Address of VertStopReg
	ADD	X0,A
	JSR	<SER_COM

	MOVE	#(MISC_REG+$F),A	; Enable windowing mode
	JSR	<SER_COM

	MOVE	#ENABLE_WM,R0		; Enable windowing mode with signal lines, too
	JSR	<CLOCK

	MOVE	#CLK_COL,R1
	MOVE	#(END_CLK_COL-CLK_COL-1),X0
	MOVE	X0,Y:(R1)
	RTS

WHOLE_FRAME
	MOVE	Y:<NROWS,A
	JCLR	#ST_CDS,X:STATUS,NO_CDS2
	LSR	A
	NOP
NO_CDS2	MOVE	A1,Y:<NROWS_CLOCK
	MOVE	Y:<NCOLS,A
	MOVE	Y:<N_SHFTS,X0
	LSR	X0,A			; n-port readout in whole image mode
	NOP
	MOVE	A1,Y:<NCOLS_CLOCK
END_SWM	MOVE	Y:<SXMIT,X0		; Transmit n channels
	MOVE	X0,Y:XMT_PXL
	MOVE	Y:<NUM_CHANS,X0
	MOVE	X0,Y:<NCHS
	MOVE	#(MISC_REG+$C),A 	; Disable windowing mode
	JSR	<SER_COM
	MOVE	#DISABLE_WM,R0		; Disable windowing mode with signal lines, too
	JSR	<CLOCK
	RTS

; Sub array readout, but not native H2RG windowing mode
NOT_WM	MOVE	Y:<SA_NCOLS,A
	MOVE	Y:<N_SHFTS,X0
	LSR	X0,A			; n-port readout in whole image mode
	NOP
	MOVE	A1,Y:<NCOLS_CLOCK
	MOVE	Y:<SA_BEGCOL,A		; One clock advances image by n coluMns
	LSR	X0,A			; n-port readout in whole image mode
	NOP
	MOVE	A1,Y:<SA_NCOLS_CK
	MOVE	Y:<SA_NROWS,A
	JCLR	#ST_CDS,X:STATUS,NO_CDS3
	LSR	A
	NOP
NO_CDS3	MOVE	A1,Y:<NROWS_CLOCK
	JMP	<END_SWM

; Specify number of readout channels. Must be 1, 4, 8, or 32.
;   NUM_CHANS and SXMIT are set here and used elsewhere to set NCHS and XMT_PXL
;   if not in windowing mode.
SPECIFY_NUMBER_OF_CHANNELS
	BSET	#ST_DIRTY,X:<STATUS
	MOVE	X:(R3)+,A
	NOP
	MOVE	A1,Y:<NUM_CHANS			; Number of channels in non-windowing mode
	CMP	#1,A
	JNE	<CMP_4
	MOVE	#0,X0
	MOVE	X0,Y:<N_SHFTS
	MOVE	#XMIT_1,X0
	MOVE	X0,Y:<SXMIT
	MOVE	#CLK_COL,R1
	BSET	#ST_RDM,X:<STATUS		; Set video readout mode to 1-by-1
	BSET	#RD_MODE,X:<LATCH
	MOVE	#(END_CLK_COL-CLK_COL-1),X0
	MOVE	X0,Y:(R1)
	MOVEP	X:LATCH,Y:WRLATCH
	MOVE	#(OUTPUT_MODE_REGISTER+$1),A 	; 1 channel readout mode
	JSR	<SER_COM
	JSR	<SETUP_READ_MODE
	JMP	<FINISH
CMP_4	CMP	#4,A
	JNE	<CMP_8
	MOVE	#>2,X0
	MOVE	X0,Y:<N_SHFTS
	MOVE	#XMIT0_3,X0
	MOVE	X0,Y:<SXMIT
	MOVE	#CLK_COL,R1
	BSET	#ST_RDM,X:<STATUS		; Set video readout mode to 1-by-1
	BSET	#RD_MODE,X:<LATCH
	MOVE	#(END_CLK_COL-CLK_COL-1),X0
	MOVE	X0,Y:(R1)
	MOVEP	X:LATCH,Y:WRLATCH
	MOVE	#(OUTPUT_MODE_REGISTER+$2),A 	; 4 channel readout mode
	JSR	<SER_COM
	JSR	<SETUP_READ_MODE
	JMP	<FINISH
CMP_8	CMP	#8,A			; Useful for testing 8-channel video boards
	JNE	<CMP_32
	MOVE	#>3,X0
	MOVE	X0,Y:<N_SHFTS
	MOVE	#XMIT0_7,X0
	MOVE	X0,Y:<SXMIT
	MOVE	#CLK_COL,R1
	BCLR	#ST_RDM,X:<STATUS		; Set video readout mode to all eight at once
	BCLR	#RD_MODE,X:<LATCH
	MOVE	#(END_CLK_COL-CLK_COL-1),X0
	MOVE	X0,Y:(R1)
	MOVEP	X:LATCH,Y:WRLATCH
	MOVE	#(OUTPUT_MODE_REGISTER+$2),A 	; 8 channel readout mode, watch out -
	JSR	<SER_COM			;  this is not supported by H2RG
	JSR	<SETUP_READ_MODE
	JMP	<FINISH
CMP_32	CMP	#32,A
	JNE	<ERROR
	MOVE	#>5,X0
	MOVE	X0,Y:<N_SHFTS
	MOVE	#XMIT_32,X0
	MOVE	X0,Y:<SXMIT
	MOVE	#CLK_COL,R1
	BCLR	#ST_RDM,X:<STATUS		; Clear video readout mode to all eight at once
	BCLR	#RD_MODE,X:<LATCH
	MOVE	#(END_CLK_COL-CLK_COL-1),X0
	MOVE	X0,Y:(R1)
	MOVEP	X:LATCH,Y:WRLATCH
	MOVE	#(OUTPUT_MODE_REGISTER+$4),A 	; 32 channel readout mode
	JSR	<SER_COM
	JSR	<SETUP_READ_MODE
	JMP	<FINISH

; Continuous readout commands
SET_NUMBER_OF_FRAMES			; Number of frames to obtain
	MOVE	X:(R3)+,X0		;   in an exposure sequence
	MOVE	X0,Y:<N_FRAMES
	JMP	<FINISH	

SET_NUMBER_OF_FRAMES_PER_BUFFER		; Number of frames in each image
	MOVE	X:(R3)+,X0		;   buffer in the host computer
	MOVE	X0,Y:<N_FPB		;   system memory
	JMP	<FINISH

SET_RESET_MODE
	JCLR	#0,X:(R3)+,NO_RESET	; 1 to reset FPA in continuous 
	BSET	#ST_RST_MODE,X:<STATUS	;   readout mode
	JMP	<FINISH
NO_RESET
	BCLR	#ST_RST_MODE,X:<STATUS
	JMP	<FINISH

SELECT_WINDOWING_MODE
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	JCLR	#0,X:(R3)+,NO_WM	; 1 to read out in native H2RG
	BSET	#ST_WM,X:<STATUS
	BSET	#ST_SA,X:<STATUS
	JMP	<FINISH
NO_WM	BCLR	#ST_WM,X:<STATUS
	BCLR	#ST_SA,X:<STATUS
	JMP	<FINISH

READ_NUMBER_OF_CHANNELS
	JSR	<SETUP_READ_MODE	; Keep NCHS updated
	MOVE	Y:<NCHS,Y1
	JMP	<FINISH1

; Select which video channel number, from 0 to 63, but only one
SELECT_VIDEO_CHANNEL_NUMBER
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE	X:(R3)+,A
	NOP
	MOVE	A1,X0
	LSL	#6,A
	NOP
	OR	X0,A
	MOVE	#$00F000,X0
	OR	X0,A
	NOP
	NOP
	MOVE	A1,Y:<SXMIT
	JMP	<FINISH

CORRELATED_DOUBLE_SAMPLE
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE	X:(R3)+,A
	BSET	#ST_DIRTY,X:<STATUS
	JCLR	#0,A1,NOT_CDS
	BSET	#ST_CDS,X:STATUS
	JMP	<FINISH
NOT_CDS	BCLR	#ST_CDS,X:<STATUS
	JMP	<FINISH

SELECT_DUAL_TRANSMITTER
	JCLR	#0,X:(R3)+,SINGLE_XMTR
	BSET	#ST_XMT2,X:<STATUS
	JMP	<FINISH
SINGLE_XMTR
	BCLR	#ST_XMT2,X:<STATUS
	JMP	<FINISH

; Select readout mode as either 
;   = 0 -> 8-channels move to the FIFO whenever XFER has a high going edge
;   = 1 -> 1-channel at a time moves to the FIFO on SXMIT

VIDEO_READOUT_MODE
	JCLR	#0,X:(R3)+,EIGHT_CHANNELS
	BSET	#ST_RDM,X:<STATUS
	BSET	#RD_MODE,X:<LATCH
	MOVEP	X:LATCH,Y:WRLATCH	; Write the bit to the IR video PAL
	JMP	<FINISH

EIGHT_CHANNELS
	BCLR	#ST_RDM,X:<STATUS
	BCLR	#RD_MODE,X:<LATCH
	MOVEP	X:LATCH,Y:WRLATCH	; Write the bit to the IR video PAL
	JMP	<FINISH

