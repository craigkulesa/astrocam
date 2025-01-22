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
	MOVE	#RST_INTERNAL_REGISTERS,R0 ; Clear the Rockwell internal registers
	JSR	<CLOCK
	JSR	<INIT_H2RG		; Initialize the Rockwell array for NIRCam 
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
	NOP
	NOP
	NOP
	DO	Y:(R0)+,L_DAC1
	MOVE	Y:(R0)+,A
	JSR	<XMIT_A_WORD
	NOP
L_DAC1
	MOVE	#>3,A
	JSR	<MILLISEC_DELAY		; Wait three milliseconds
	BSET	#ENCK,X:<LATCH		; Enable clock and DAC output switches
	MOVEP	X:LATCH,Y:WRLATCH	; Write it to the hardware

	MOVE	Y:VDD_ON,A
	JSR	<XMIT_A_WORD		; VDD turns on first
	MOVE	#>10,A
	JSR	<MILLISEC_DELAY		; Wait ten milliseconds

	MOVE	#VDDA_ON,R0
	DO	#4,L_VDDA_ON
	MOVE	Y:(R0)+,A
	JSR	<XMIT_A_WORD		; VDDA #1-4 go next
	NOP
L_VDDA_ON
	MOVE	#>10,A
	JSR	<MILLISEC_DELAY		; Wait ten milliseconds
	
	DO	#(END_DACS-VDDA_ON-4),L_DC_ON
	MOVE	Y:(R0)+,A
	JSR	<XMIT_A_WORD		; Remaining DC biases go next
	NOP
L_DC_ON	
	MOVE	#>10,A
	JSR	<MILLISEC_DELAY		; Wait ten milliseconds	
	MOVE	#DACS,R0
	DO	#(VDDA_ON-DACS),L_CLK_ON
	MOVE	Y:(R0)+,A
	JSR	<XMIT_A_WORD		; Clocks go last
	NOP
L_CLK_ON
	MOVE	#>10,A
	JSR	<MILLISEC_DELAY		; Wait ten milliseconds

	BCLR	#3,X:PCRD		; Turn the serial clock off
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
	NOP
	NOP
	NOP
	DO	Y:(R0)+,L_DAC2
	MOVE	Y:(R0)+,A
	JSR	<XMIT_A_WORD
	NOP
L_DAC2
	MOVE	#$0C3001,A	; Slow integrate speed
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

; Fast clear of FPA, executed as a command
CLEAR	JSR	<RESET_ARRAY
	JMP     <FINISH

; Start the exposure timer and monitor its progress
EXPOSE	MOVEP	#0,X:TLR0		; Load 0 into counter timer
	MOVE	X:<EXPOSURE_TIME,B
	TST	B			; Special test for zero exposure time
	JEQ	<END_EXP		; Don't even start an exposure
	SUB	#1,B			; Timer counts from X:TCPR0+1 to zero
	BSET	#TIM_BIT,X:TCSR0	; Enable the timer #0
	MOVE	B,X:TCPR0
CHK_RCV	MOVE	#<COM_BUF,R3		; The beginning of the command buffer
	JCLR    #EF,X:HDR,CHK_TIM	; Simple test for fast execution
	JSR	<GET_RCV		; Check for an incoming command
	JCS	<PRC_RCV		; If command is received, go check it
CHK_TIM	JCLR	#TCF,X:TCSR0,CHK_RCV	; Wait for timer to equal compare value
END_EXP	BCLR	#TIM_BIT,X:TCSR0	; Disable the timer
	JMP	(R7)			; This contains the return address

; Start the exposure and initiate FPA readout
START_EXPOSURE
	MOVE	#$020102,B		; Initialize the PCI image address
	JSR	<XMT_WRD
	MOVE	#'IIA',B
	JSR	<XMT_WRD

; Reset the shift registers of the vertical and horizontal scanners
 	JSET	#ST_WM,X:STATUS,RST_SR
	MOVE	#MISC_REG,A		; Not windowing mode 
	JSR	<SER_COM
	MOVE	#(MISC_REG+$C),A 
	JSR	<SER_COM
	JMP	<SET_WM
RST_SR	MOVE	#(MISC_REG+3),A		; Windowing mode
	JSR	<SER_COM
	MOVE	#(MISC_REG+$F),A 
	JSR	<SER_COM
	
; Update the FPA serial command registers if needed
SET_WM	JCLR	#ST_DIRTY,X:STATUS,RST_FPA
	JSR	<SETUP_WINDOW_MODE	; Setup window mode readout (or not)
	BCLR	#ST_DIRTY,X:STATUS

RST_FPA	JSR	<RESET_ARRAY
	JSR	<SETUP_SXMIT		; Restore series transmit of A/D values
	MOVE	#TST_RCV,R0		; Process commands, don't idle, 
	MOVE	R0,X:<IDL_ADR		;    during the exposure

	DO	Y:<NUTR,L_UP_THE_RAMP
	MOVE	#L_SEX1,R7		; Return address at end of exposure
	JSR	<WAIT_TO_FINISH_CLOCKING
	JMP	<EXPOSE			; Delay for specified exposure time
L_SEX1

; Check for host computer commands before starting each readout
	MOVE	#COM_BUF,R3
	JSR	<GET_RCV		; Was a command received?
	JCC	<CONTINUE_READ		; If no, continue reading out
	JMP	<PRC_RCV		; If yes, go process it
ABR_RDC	ENDDO				; Properly terminate readout loop
	JMP	<ABORT_EXPOSURE
CONTINUE_READ
	JSR	<RD_ARRAY		; Finally, go read out the FPA
	NOP
L_UP_THE_RAMP				; Up the ramp loop
	JMP	<START

; Set the desired exposure time
SET_EXPOSURE_TIME
	MOVE	X:(R3)+,Y0
	MOVE	Y0,X:EXPOSURE_TIME
	MOVEP	X:EXPOSURE_TIME,X:TCPR0
	JMP	<FINISH

; Read the time remaining until the exposure ends
READ_EXPOSURE_TIME
	MOVE	X:TCR0,Y1		; Read elapsed exposure time
	JMP	<FINISH1

; Pause the exposure - just stop the timer
PAUSE_EXPOSURE
	MOVEP	X:TCR0,X:ELAPSED_TIME	; Save the elapsed exposure time
	BCLR    #TIM_BIT,X:TCSR0	; Disable the DSP exposure timer
	JMP	<FINISH

; Resume the exposure - just restart the timer
RESUME_EXPOSURE
	BSET	#TRM,X:TCSR0		; To be sure it will load TLR0
	MOVEP	X:TCR0,X:TLR0		; Restore elapsed exposure time
	BSET	#TIM_BIT,X:TCSR0	; Re-enable the DSP exposure timer
	JMP	<FINISH

; See if the command issued during readout is a 'ABR'. If not continue readout
CHK_ABORT_COMMAND
	MOVE	X:(R3)+,X0		; Get candidate header
	MOVE	#$000202,A 
	CMP	X0,A
	JNE	<RD_CONT
WT_COM	JSR	<GET_RCV		; Get the command
	JCC	<WT_COM
	MOVE	X:(R3)+,X0		; Get candidate header
	MOVE	#'ABR',A 
	CMP	X0,A
	JEQ	<ABR_RDC
RD_CONT	MOVE	#<COM_BUF,R3		; Continue reading out the FPA
	MOVE	R3,R4
	JMP	<CONTINUE_READ

; Special ending after abort command to send a 'DON' to the host computer
RDFPA_END_ABORT
	MOVE	#100000,X0
	DO      X0,*+3			; Wait one millisec
	NOP
	JCLR	#IDLMODE,X:<STATUS,NO_IDL2 ; Don't idle after readout
	MOVE	#CONT_RST,R0
	MOVE	R0,X:<IDL_ADR
	JMP	<RDC_E2
NO_IDL2	MOVE	#TST_RCV,R0
	MOVE	R0,X:<IDL_ADR
RDC_E2	JSR	<WAIT_TO_FINISH_CLOCKING
	BCLR	#ST_RDC,X:<STATUS	; Set status to not reading out

	MOVE	#$000202,X0		; Send 'DON' to the host computer
	MOVE	X0,X:<HEADER
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
	MOVE	Y:<NCOLS_XMIT,B		; Number of columns to read
	JSR	<XMT_WRD
	MOVE	Y:<NROWS_XMIT,B		; Number of rows to read
	JSR	<XMT_WRD
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
	NOP
	MOVE	A1,Y:0
	JSR	<XMIT_A_WORD	; Transmit A to TIM-A-STD
	JSR	<PAL_DLY	; Wait for the number to be sent
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<FINISH
ERR_SBN	MOVE	X:(R3)+,A	; Read and discard the fourth argument
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<ERROR

; The command is for the DC biases on the ARC-46 video board
VID_SET
	LSL	#14,A		; Put the DAC number 0-7 into bits 16-14
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
	REP	#20
	LSL	A
	NOP
	MOVE	A,X1		; Board number, bits 23-20
	MOVE	X:(R3)+,A	; Second argument is DAC number
	LSL	#14,A		; Put the DAC number 0-7 into bits 16-14
	NOP
	BSET	#19,A1		; Set bits 19-17 to mean video offset DAC
	NOP
	BSET	#18,A1
	NOP
	BSET	#17,A1
	MOVE	X:(R3)+,X0	; Fourth argument is voltage value for ARC46,
	OR	X0,A		;  12 bits, bits 11-0
	OR	X1,A		; Add on the board number, bits 23-20
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
	REP	#20
	LSL	A
	MOVE	#$003000,X0
	OR	X0,A
	NOP
	MOVE	A,X1		; Move here for storage

; Get the first MUX number
	MOVE	X:(R3)+,A	; Get the first MUX number
	JLT	ERR_SM1
	MOVE	#>24,X0		; Check for argument less than 32
	CMP	X0,A
	JGE	ERR_SM1
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
	JLT	<ERROR
	MOVE	#>24,X0		; Check for argument less than 32
	CMP	X0,A
	JGE	<ERROR
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
	JNE	<ERROR
	BSET	#11,B1
SMX_B	ADD	Y1,B		; Add prefix to MUX numbers
	NOP
	MOVE	B1,A
	JSR	<XMIT_A_WORD	; Transmit A to TIM-A-STD
	JSR	<PAL_DLY	; Delay for all this to happen
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<FINISH
ERR_SM1	MOVE	X:(R3)+,A
	BCLR	#3,X:PCRD	; Turn the serial clock off
	JMP	<ERROR


;***********  Special NIRCam commands *******************

; This should clear the array when the 'Clear Array' button in the 
;   main Voodoo window is pressed.
CLR_ARRAY
	JSR	<RESET_ARRAY
	JMP	<FINISH

; Set the number of exposures for up-the-ramp readout mode
NUMBER_UP_THE_RAMP
	MOVE	X:(R3)+,X0
	MOVE	X0,Y:<NUTR
	JMP	<FINISH

; Transmit a serial command to the Rockwell array(s)
SER_COM	MOVE	Y:<NSCA,B
; !!!	CMP	#1,B
; !!!	JEQ	<ONE_SCA
	MOVE	#ALL_CSB_LOW,R0		; Enable all serial command links
	JSR	<CLOCK
	JMP	<NEXT
ONE_SCA	MOVE	#ONE_CSB_LOW,R0		; Enable one serial command link
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
	MOVE	X:(R3)+,A
	JSR	<SER_COM		; Send it to H2RG
	JMP	<FINISH

; Assert MAINRESETB to clear all internal registers to default settings
RESET_INTERNAL_REGISTERS
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE	#RST_INTERNAL_REGISTERS,R0
	JSR	<CLOCK
	JMP	<FINISH

; Initialize the internal registers to default NIRCam settings
INIT_H2RG
	BSET	#ST_DIRTY,X:<STATUS			; @@@ A readout parameter will be changed
	MOVE	#(NORMAL_MODE_REG+%00000011),A		; Normal mode is 
	JSR	<SER_COM				;  enhanced clocking
	MOVE	#(WINDOW_MODE_REG+%00000011),A		; Windowing mode is	
	JSR	<SER_COM				;  enhanced clocking
	RTS

INITIALIZE_H2RG_TO_NIRCAM
	JSR	<INIT_H2RG
	JMP	<FINISH

; Specify subarray readout size
SET_SUBARRAY_SIZE
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE    X:(R3)+,X0		; Not used
	MOVE    X:(R3)+,A		; Whole array mode if ncols = 0 
	TST	A
	JEQ	<WHOLE_ARRAY_MODE
	MOVE	A1,Y:<WM_NCOLS		; Number of columns in subimage read
	MOVE    X:(R3)+,X0
	MOVE	X0,Y:<WM_NROWS		; Number of rows in subimage read	
	BSET	#ST_WM,X:<STATUS
	JMP	<FINISH

WHOLE_ARRAY_MODE
	BCLR	#ST_WM,X:<STATUS
	JMP	<FINISH

; Specify subarray readout position
SET_SUBARRAY_POSITION
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE	X:(R3)+,X0
	MOVE	X0,Y:<WM_STARTROW	; Number of rows skip over
	MOVE	X:(R3)+,X0
	MOVE	X0,Y:<WM_STARTCOL	; Number of columns to skip over
	MOVE	X:(R3)+,X0		; Not used
	BSET	#ST_WM,X:<STATUS	; @@@
	JMP	<FINISH

; Specify the delay time between clocking a row and beginning to read
SET_READ_DELAY
	MOVE	X:(R3)+,X0
	MOVE	X0,Y:<READ_DELAY
	JMP	<FINISH

; Specify number of H2RG arrays in the system
SET_NUMBER_OF_ARRAYS
	BSET	#ST_DIRTY,X:<STATUS	; A readout parameter will be changed
	MOVE	X:(R3)+,A		; Must be either 1 or 4
	CMP	#1,A
	JEQ	<EQ_1			
	CMP	#4,A
	JNE	ERROR
EQ_1	MOVE	A1,Y:<NSCA
	JMP	<FINISH	

; Test for windowing mode = subarray readout
SETUP_WINDOW_MODE
	JCLR	#ST_WM,X:STATUS,WHOLE_FRAME
	MOVE	Y:<WM_STARTCOL,A
	MOVE	#HORIZ_START_REG,X0	; Address of HorizStartReg
	ADD	X0,A
	JSR	<SER_COM
	MOVE	Y:<WM_NCOLS,X0
	MOVE	X0,Y:<NCOLS_CLOCK
	MOVE	Y:<WM_STARTCOL,A
	ADD	X0,A
	MOVE	#HORIZ_STOP_REG,X0	; Address of HorizStopReg
	ADD	X0,A
	JSR	<SER_COM
	MOVE	Y:<WM_STARTROW,A
	MOVE	#VERT_START_REG,X0	; Address of VertStartReg
	ADD	X0,A
	JSR	<SER_COM
	MOVE	Y:<WM_NROWS,X0
	MOVE	X0,Y:<NROWS_CLOCK
	MOVE	Y:<WM_STARTROW,A
	ADD	X0,A
	MOVE	#VERT_STOP_REG,X0	; Address of VertStopReg
	ADD	X0,A
	JSR	<SER_COM
	RTS

WHOLE_FRAME	
	MOVE	Y:<NROWS_ARRAY,X0
	MOVE	X0,Y:<NROWS_CLOCK
	MOVE	Y:<NCOLS_ARRAY,A
	LSR	#2,A			; 4-port readout in whole image mode
	NOP
	MOVE	A1,Y:<NCOLS_CLOCK
	RTS
	
; Get the controller to transmit the correct number of pixel data
SETUP_SXMIT
	MOVE	Y:<NSCA,A
	CMP	#4,A
	JEQ	<MOSAIC
	JCLR	#ST_WM,X:STATUS,WHOLE_FRAME_SXMIT

; This is windowing readout from a single H2RG
	MOVE	#XMT_PXL,R0
	MOVE	#>$7,X1			; Don't disturb the video processor
	MOVE	Y:<SEL_FPA_WM,X0	; Only one readout: #0, 4, 8 or C
	MOVE	X0,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	Y:<WM_NCOLS,X0
	MOVE	X0,Y:<NCOLS_XMIT
	MOVE	Y:<WM_NROWS,X0
	MOVE	X0,Y:<NROWS_XMIT
	RTS

; This is whole frame readout from a single H2RG
WHOLE_FRAME_SXMIT
	MOVE	#XMT_PXL,R0
	MOVE	#>$7,X1		; Don't disturb the video processor
	MOVE	Y:<SEL_FPA,X0
	MOVE	X0,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	Y:<NCOLS_ARRAY,X0
	MOVE	X0,Y:<NCOLS_XMIT
	MOVE	Y:<NROWS_ARRAY,X0
	MOVE	X0,Y:<NROWS_XMIT
	RTS

; This is readout from a 2x2 mosaic of H2RGs
MOSAIC	JCLR	#ST_WM,X:STATUS,WHOLE_FRAME_SXMIT_MOSAIC

; This is windowing readout from a 2x2 mosaic of H2RGs
	MOVE	#XMT_PXL,R0
	MOVE	#>$7,X1		; Don't disturb the video processor
	MOVE	#XMIT0,X0
	MOVE	X0,Y:(R0)+	; Readouts #0, #4, #8 and #C
	MOVE	X1,Y:(R0)+
	MOVE	#XMIT4,X0
	MOVE	X0,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	#XMIT8,X0
	MOVE	X0,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	#XMITC,X0
	MOVE	X0,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	Y:<WM_NCOLS,A	; The same windows from all four
	LSL	A		;  H2RGs are being transmitted
	NOP
	MOVE	A1,Y:<NCOLS_XMIT
	MOVE	Y:<WM_NROWS,A
	LSL	A
	NOP
	MOVE	A1,Y:<NROWS_XMIT
	RTS

; This is whole frame readout from a 2x2 mosaic of H2RGs
WHOLE_FRAME_SXMIT_MOSAIC
	MOVE	#XMT_PXL,R0
	MOVE	#>$7,X1		; Don't disturb the video processor
	MOVE	#XMIT0_F,X0	; Readouts #0 to #15
	MOVE	X0,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	X1,Y:(R0)+
	MOVE	Y:<NCOLS_ARRAY,A	; Transmit data from
	LSL	A			;  all four H2RGs
	NOP
	MOVE	A1,Y:<NCOLS_XMIT
	MOVE	Y:<NROWS_ARRAY,A
	LSL	A
	NOP
	MOVE	A1,Y:<NROWS_XMIT
	RTS

; In single readout mode select which of the four arrays to read from 
SELECT_OUTPUT_SOURCE
	BSET	#ST_DIRTY,X:<STATUS
	MOVE	X:(R3)+,X0		; Number of array = 0, 1, 2 or 3

	MOVE	#0,A
	CMP	X0,A
	JNE	<CMP_1	
	MOVE	#XMIT0_3,Y0
	MOVE	Y0,Y:<SEL_FPA
	MOVE	#XMIT0,Y0
	MOVE	Y0,Y:<SEL_FPA_WM
	JMP	<FINISH

CMP_1	MOVE	#>1,A
	CMP	X0,A
	JNE	<CMP_2
	MOVE	#XMIT4_7,Y0
	MOVE	Y0,Y:<SEL_FPA
	MOVE	#XMIT4,Y0
	MOVE	Y0,Y:<SEL_FPA_WM
	JMP	<FINISH

CMP_2	MOVE	#>2,A
	CMP	X0,A
	JNE	<CMP_3
	MOVE	#XMIT8_B,Y0
	MOVE	Y0,Y:<SEL_FPA
	MOVE	#XMIT8,Y0
	MOVE	Y0,Y:<SEL_FPA_WM
	JMP	<FINISH

CMP_3	MOVE	#>3,A
	CMP	X0,A
	JNE	<ERROR
	MOVE	#XMITC_F,Y0
	MOVE	Y0,Y:<SEL_FPA
	MOVE	#XMITC,Y0
	MOVE	Y0,Y:<SEL_FPA_WM
	JMP	<FINISH

