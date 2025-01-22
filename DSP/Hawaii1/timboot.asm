; This file is used to generate DSP boot code for the second generation 
;   TimII timing board, Rev. 4B.     

	PAGE    132     ; Printronix page width - 132 columns

; Include a header file that defines global parameters
   INCLUDE "HAWHead.asm"

; After RESET jump to the initialization code
	ORG     P:RST_ISR,P:RST_ISR+ROM_OFF 
	JMP	<INIT		; Initialize DSP after hardware reset
	NOP

; DSP Timer interrupt for exposure time control
	ORG     P:TIM_ISR,P:TIM_ISR+ROM_OFF
	JSR     <TIMER          ; Long interrupt service routine
	NOP

; Put some words identifying this version of the ROM code. It is placed at
;   the address of the SWI = software interrupt, which is never used. 
        ORG     P:ROM_ID,P:ROM_ID+ROM_OFF
        DC      $000000         ; Institution
                                ; Location
                                ; Instrument
        DC      $030002         ; Version 3.00, board #2 = timing

;**************************************************************************
;                                                                         *
;    Permanent address register assignments                               *
;        R3 - Pointer to commands received pending processing             *
;        R4 - Pointer to processed commands		                  *
;        R6 - CCD clock driver address for CCD #0                         *
;                It is also the A/D address of analog board #0            *
;                                                                         *
;    Other registers 							  *
;	 R1, R2, R5 - Not used very much				  *
;        R0, R7 - Temporary registers used all over the place             *
;**************************************************************************

; Initialization code is in the application area since it executes only once
	ORG	P:APL_ADR,P:APL_ADR+ROM_OFF	; Download address

; Initialization of the DSP - system register, serial link, interrupts.
;    This is executed once on DSP boot from ROM, and is not incorporated
;    into any download code since its not needed.
	
INIT	MOVEC   #$0002,OMR	; Operating Mode Register = Normal 
				;   Expanded - set after reset by hardware

	ORI     #$03,MR         ; Mask interrupts

	MOVEP	#0,X:PBC	; Port B Control Register to Parallel I/O

	MOVEP	#$050D,X:PBD	; Port B Data Register
				;   H0=0 -> utility board SSI, WW=0 -> 24-bit
				;   STATUS 0 to 3 = 0, AUX1=1, FD15 = 0,
				;   LVEN = HVEN = 1, PWRST = 0 

	MOVEP	#$15FF,X:PBDDR	; Port B Data Direction Register
				;   Set signals listed in PBD above to outputs
				;   and SYNC to an input

        MOVEP   #$6002,X:CRA    ; SSI programming - no prescaling; 
				;   24 bits/word; on-demand communications; 
				;   no prescale; 4.17 MHz serial clock rate

	MOVEP   #$3D30,X:CRB    ; SSI programming - OF0, OF1 don't apply; 
				;   SC0, SC1, SC2 are inputs; SCK is output;
				;   shift MSB first; rcv and xmt asynchronous
				;   wrt each other; gated clock; bit frame 
                                ;   sync; network mode to get on-demand; 
                                ;   RCV and TX enabled, RCV and TX interrrupts
		 		;   disabled -> Utility board SSI

	MOVEP   #$01E8,X:PCC	; Port C Control Register

	MOVEP	#$0007,X:PCD	; Port C Data Register

	MOVEP	#$0007,X:PCDDR	; Port C Data Direction Register
				;   Set signals listed in PCD above to outputs

	MOVEP   #>2,X:TCSR      ; Enable timer interrupts

	MOVEP   #$61A8,X:TCR    ; Divide so timer interrupts every millisecond

; Clear all video processor analog switches to lower their power dissipation
	BSET	#0,X:PBD	; Set H0 for analog boards SSI
	MOVEP	#$0000,X:PCC	; Software reset of SSI
	BCLR	#10,X:CRB	; Change SSI to continuous clock for analog 
	MOVEP   #$0160,X:PCC	; Re-enable the SSI
	DO	#500,*+3	; Wait 8 usec for serial data transmission
	NOP

	MOVE	#$0C3000,A
	CLR	B
	MOVE	#$100000,X0
	MOVE	#$001000,X1
	DO	#15,L_VIDEO	; Fifteen video processor boards maximum
	MOVEP	A,X:SSITX 	; Gain, integrate speed
	ADD	X0,A
	MOVE	B,X:WRSS
	ADD	X1,B
	DO	#500,*+3	; Wait 8 usec for serial data transmission
	NOP	
	NOP
L_VIDEO	

; Initialize the synchronous serial port
	MOVEP	#$0000,X:PCC	; Software reset of SSI
	BSET	#10,X:CRB	; Change SSI to gated clock for utility board 
	MOVEP   #$0160,X:PCC	; Enable the SSI
	BCLR	#0,X:PBD	; Clear H0 for utility board SSI

; Initialize X: data DSP memory
	MOVE    #RD_X,R0 	; Starting X: address in EEPROM
        MOVE    #0,R1		; Put values starting at beginning of X:
	DO      #$100,X_MOVE	; Assume 256 = $100 values exist
        DO      #3,X_LOOP	; Reconstruct bytes to 24-bit words
        MOVE    P:(R0)+,A2	; Get one byte from EEPROM
	REP	#8
        ASR     A  		; Shift right 8 bits
	NOP			; DO loop restriction
X_LOOP
        MOVE    A1,X:(R1)+	; Write 24-bit words to X: memory
X_MOVE

; Reset the utility board to force it to re-boot
	BCLR	#TIM_U_RST,X:<LATCH	
	MOVEP	X:LATCH,Y:WRLATCH 	; Clear reset utility board bit
	REP	#200			; Delay by RESET* low time
	NOP
	BSET	#TIM_U_RST,X:<LATCH	
	MOVEP	X:LATCH,Y:WRLATCH 	; Clear reset utility board bit
	MOVE	#10000,A		; Delay for utility boot < 1 msec
	DO	A,*+3
	NOP

; Initialize the permanent registers
        MOVE    #<RCV_BUF,R3	; Starting address of command buffer
        MOVE    #WRSS,R6	; Address of clock and video processor switches
	MOVE	#<TST_RCV,R0	; Execution address when idle => when not
	MOVE	R0,X:<IDL_ADR	;   processing commands or reading out
	CLR	A  R3,R4
	MOVE	#31,M3		; Buffers are circular, modulo 32
	MOVE	M3,M4
	DO	#32,ZERO_X	; Zero receiver buffer
	MOVE	A,X:(R3)+
ZERO_X

; Reset the input command FIFO
	BCLR	#RST_FIFO,X:<LATCH
	MOVEP	X:LATCH,Y:WRLATCH
	BSET	#RST_FIFO,X:<LATCH
	MOVEP	X:LATCH,Y:WRLATCH

; Set the interrupt priority level for the DSP timer
	MOVEP   #$030000,X:IPR	; Exposure timer priority = 2
	ANDI    #$FC,MR         ; Unmask all interrupt levels

; Specify the external memory space wait states
	MOVEP	#$0111,X:BCR	; Wait states = X: Y: P: and Y: ext. I/O

; Reply to the host computer that the system re-booted
	MOVE	#$020002,A
	MOVE	A,X:(R3)+
	MOVE	#'SYR',A
	MOVE	A,X:(R3)+

; Go execute the program - initialization is over
	JMP	<PRC_RCV	; Go look for incoming commands

; Check for program space overflow
        IF	@CVS(N,*)>$1FF
        WARN    'Internal P: memory overflow!'	; Don't overflow DSP P: space
	ENDIF

;  ****************  Beginning of command execution code  ******************

; Start the code in the interrupt vector area that is not used
	ORG     P:START,P:START+ROM_OFF	; Program start at P:$18

; Return here after executing each command
	MOVE	#<RCV_BUF,R3
	MOVE	R3,R4
	MOVE	X:<IDL_ADR,R0
	BSET	#ST_RCV,X:STATUS	; Assume its NOT an SSI word
	JSET    #TIM_BIT,X:TCSR,CHK_TIM	; If exposing go check timer
	JMP	(R0)

TST_RCV	JSR	<GET_RCV	; Look for pending serial words
	JCC	<TST_RCV	; If none, then keep checking

; First check for requests for service from the utility board
CHK_SSI	JSET	#ST_RCV,X:<STATUS,HEADER ; Only check if its a FIFO word
	MOVE	X:-(R3),Y0	; Get candidate header
	MOVE	X:<UTL_REQ,A	; Is it the utility board requesting service?
	CMP	Y0,A
	JEQ	<GET_UTL	; Yes, go get the rest of utility board words

; Check the header (S,D,N) for self-consistency
HEADER	MOVE	X:-(R3),X0	; Get candidate header
	JSR	<CHK_HDR	; Go check it; A1 = NWORDS
	MOVE	X0,X:<HDR	; Save the header
	JCS	<START		; Error if carry bit is set - discard header

; Read all the words of the command before processing the command
	MOVE	R4,X0		; Header address = RCV_BUF
	ADD	X0,A (R3)+	; R3 must reach this for command to be complete
	MOVE	A,X1		; X1 = header address + NWORDS

; Implement a timeout
	DO	X:<TIM_COM,TIME_OUT
	JSR	<GET_RCV
	JCC	<NOT_YET
	MOVE	R3,A		; Get address of last word written to buffer
	CMP	X1,A		; Has it been incremented to RCV_BUF + NWORDS?
	JLT	<NOT_YET	; No, keep looking for more
	ENDDO
	JMP	<PRC_RCV	; Go process the entire command normally
NOT_YET	NOP
TIME_OUT
	JSR	<CHK_ERR	; Reset either the FIFO or the SSI
	JMP	<START		; Start over

; Process the receiver entry - is its destination number = D_BRD?
PRC_RCV	MOVE	R3,A            ; Pointer to current contents of receiver
	MOVE	R4,X0           ; Pointer to processed contents
	CMP	X0,A  X:(R4),X0	; Are they equal? Get header for later
	JEQ	<START		; If unequal, process command
	MOVE	#7,A1
	AND	X0,A  X:<DMASK,B1 	; Extract NWORDS
	AND	X0,B  X:<DBRD,X1 	; Extract destination byte
	CMP	X1,B  A1,X:<NWORDS 	; Does header = destination number? 
	JEQ	<COMMAND		; Yes, process it as a command
	JLT	<FO_XMT			; Send to fiber optic transmitter?
	JMP	<XMT_UTL

; Transmit words to the utility board over the SSI
XMT_UTL	DO      X:<NWORDS,DON_XMT 	; Transmit NWORDS
	JCLR    #SSI_TDE,X:SSISR,*	; Continue if SSI XMT register is empty
        MOVEP	X:(R4)+,X:SSITX		; Write to SSI buffer
DON_XMT 
	JMP     <PRC_RCV		; Check command continuation

; Check for program space overwriting of timer ISR
	IF      @CVS(N,*)>$3C
	WARN    'Error: Timer ISR overwitten at P:$3C'
	ENDIF

	ORG     P:PGM_CON,P:PGM_CON+ROM_OFF     ; Step over timer ISR

; Transmit words to the host computer over the fiber optics link
FO_XMT	DO	X:<NWORDS,DON_FFO 	; Transmit all the words in the command
	DO	#40,DLY_FFO		; Delay for the serial transmitter
        NOP
DLY_FFO
	MOVEP	X:(R4)+,Y:WRFO		; Send each word to the fo transmitter
DON_FFO
	JMP	<PRC_RCV

; Process the receiver entry - is it in the command table ?
COMMAND	MOVE    (R4)+           ; Increment over the header
	MOVE    X:(R4)+,A       ; Get the command buffer entry
	MOVE	#<COM_TBL,R0 	; Get command table starting address
	DO      #NUM_COM,END_COM ; Loop over the command table
	MOVE    X:(R0)+,X1      ; Get the command table entry
	CMP     X1,A  X:(R0),R5	; Does receiver = table entries address?
	JNE     <NOT_COM        ; No, keep looping
	ENDDO                   ; Restore the DO loop system registers
	JMP     (R5)            ; Jump execution to the command
NOT_COM MOVE    (R0)+           ; Increment the register past the table address
END_COM

; It's not in the command table - send an error message
ERROR   MOVE    X:<ERR,X0	; Send the message - there was an error
        JMP     <FINISH1	; This protects against unknown commands

; Send a reply packet - header and reply
FINISH  MOVE    X:<DON,X0	; Send a DONE message as a reply
FINISH1	MOVE    X:<HDR,A	; Get header of incoming command
        MOVE    X:<SMASK,Y0	; This was the source byte, and is to 
	AND     Y0,A  X:<TWO,Y0	;    become the destination byte
        REP	#8		; Shift right one byte, add it to the
        LSR     A  Y0,X:<NWORDS	;     header, and put 2 as the number
        ADD     Y0,A  X:<SBRD,Y0 ;    of words in the string
	ADD	Y0,A		; Add source board's header, set X1 for above
        MOVE    A,X:(R3)+       ; Put header on the transmitter stack
	MOVE	X0,X:(R3)+	; Put value of XO on the transmitter stack
	JMP	<PRC_RCV	; Go transmit these words

; Read the FIFO data one byte at a time and construct a 3-byte word
GET_RCV	JCLR	#ST_RCV,X:<STATUS,GET_SSI
	JCLR    #EF,X:PBD,GET_SSI
	JCLR    #EF,X:PBD,GET_SSI	; Protection against metastability
	CLR	A
	MOVE	A,Y1
	MOVE	X:<EIGHT,A0
	MOVE	A0,Y0
	DO	#3,L_WORD		; Process three bytes per word
	CLR	B

; Because of FIFO metastability require that EF be stable for two tests
TST1	JCLR    #EF,X:PBD,TST2		; EF = Low,  Low  => END_DO
	JMP	<TST3			;      High, Low  => try again
TST2	JCLR    #EF,X:PBD,END_DO	;      Low,  High => try again
	JMP	<TST1			;      High, High => read FIFO
TST3	JCLR	#EF,X:PBD,TST1
	MOVEP	Y:RDFO,B2		; Read the next byte of FIFO data
	JMP	<L_INCR

END_DO	ENDDO			; ENDDO the L_WORD DO loop above
	JMP	<CLR_RTS

L_INCR	DO	A0,L_ASR	; Shift a byte from B2 into B1
	ASR	B
	BCLR	#7,B2
L_ASR
	ADD	Y,A		; Increment the LSB of A for DO loop argument
	MOVE	B1,X0
	OR	X0,A		; Add in the current byte to the word
L_WORD
	MOVE	A1,X:(R3)+	; Put the word in the RCV buffer
	BSET	#ST_RCV,X:<STATUS
	JMP	<SET_RTS	; Set status register carry bit and return

GET_SSI	JCLR	#SSI_RDF,X:SSISR,CLR_RTS
	MOVEP   X:SSIRX,X:(R3)+	; Put the word in the SSI receiver buffer
	BCLR	#ST_RCV,X:<STATUS
SET_RTS	BSET	#0,SR		; Valid FIFO word => SR carry bit = 1
	RTS
CLR_RTS	BCLR	#0,SR		; Not valid FIFO word => SR carry bit = 0
	RTS

; Acknowledge the utility board request and wait for a normal header word
GET_UTL	JCLR    #SSI_TDE,X:SSISR,*	; Wait for transmitter to be empty
	MOVEP	X:TIM_ACK,X:SSITX	; Write acknowledge to utility board
	JCLR	#SSI_RDF,X:SSISR,*	; Wait for next utility board word
	MOVEP   X:SSIRX,X:(R3)+		; Overwrite UTL_REQ word
	JMP	<HEADER			; Process it as normal header word

; Check the header word (S,D,N) contained in X0 for self-consistency
CHK_HDR	MOVE    X:<MASK1,A1	; Test for S.LE.3 and D.LE.3 and N.LE.7
	AND     X0,A		
	JNE     <CHK_ERR	; Test failed
	MOVE    X:<MASK2,A1
	AND     X0,A		; Test for either S.NE.0 or D.NE.0
       	JEQ     <CHK_ERR	; Test failed
	MOVE	X:<SEVEN,A1
        AND     X0,A  		; Test for NWORDS .GE. 1
	JEQ	<CHK_ERR
	BCLR	#0,SR		; Check OK - header is self-consistent
	RTS

; Clear the FIFO and restart R3 and R4
CHK_ERR	JCLR	#ST_RCV,X:<STATUS,CLR_SSI
	BCLR	#RST_FIFO,X:<LATCH 	; Clear the FIFO
	MOVEP	X:LATCH,Y:WRLATCH
	BSET	#RST_FIFO,X:<LATCH
	MOVEP	X:LATCH,Y:WRLATCH
	JMP	<RTS_ERR
CLR_SSI	MOVEP	#$0000,X:PCC		; Software reset of SSI
	MOVEP   #$01E8,X:PCC		; Enable the SSI
RTS_ERR	BSET	#0,SR
	RTS

; Start up the exposure timer and check for incoming commands during
;  the exposure countdown
EXPOSE  MOVE	X:<EXP_TIM,A		; Enter exposure time into timer's
	MOVE	A,X:<TGT_TIM		;   target time
	CLR	A			; Zero out elapsed time
	MOVE	A,X:<EL_TIM
	BSET	#TIM_BIT,X:TCSR		; Enable the DSP timer
CHK_RCV	JSR	<GET_RCV		; Check for an incoming command
	JCS	<CHK_SSI		; If command is received, go check it
CHK_TIM	JSET	#TIM_BIT,X:TCSR,CHK_RCV	; Wait for timer to end
	JMP	(R7)			; Jump to the internal jump address

; Interrupt service routine for the DSP timer, called every millisecond
TIMER   MOVEC   SR,X:<SV_SR             ; Save registers used in this ISR
	MOVE    B0,X:<SV_B0
	MOVE    B1,X:<SV_B1
	MOVE    B2,X:<SV_B2
	MOVE    Y1,X:<SV_Y1
	MOVE    X:<ONE,B
	MOVE    X:<EL_TIM,Y1            ; Get elapsed time
	ADD     Y1,B  X:<TGT_TIM,Y1     ; Get target time
	MOVE    B,X:<EL_TIM             ; EL_TIM = EL_TIM + 1
	CMP     Y1,B    
	JLT     <NO_TIM                 ; If (EL .GE. TGT) we've timed out
	BCLR    #TIM_BIT,X:TCSR		; Disable timer
NO_TIM  MOVEC   X:<SV_SR,SR             ; Restore saved registers
	MOVE    X:<SV_B0,B0
	MOVE    X:<SV_B1,B1
	MOVE    X:<SV_B2,B2
	MOVE    X:<SV_Y1,Y1
	RTI                             ; Return from TIMER interrupt

; Test Data Link - simply return value received after 'TDL'
TDL	MOVE    X:(R4)+,X0      ; Get data value
        JMP     <FINISH1	; Return from executing TDL command

; Read DSP or EEPROM memory ('RDM' address): read memory, reply with value
RDMEM	MOVE    X:(R4),R0	; Need the address in an address register
	MOVE	X:(R4)+,A	; Need address also in a 24-bit register
        JCLR    #20,A,RDX 	; Test address bit for Program memory
	MOVE	P:(R0),X0	; Read from Program Memory
        JMP     <FINISH1	; Send out a header with the value
RDX     JCLR    #21,A,RDY 	; Test address bit for X: memory
        MOVE    X:(R0),X0	; Write to X data memory
        JMP     <FINISH1	; Send out a header with the value
RDY     JCLR    #22,A,RDR	; Test address bit for Y: memory
        MOVE    Y:(R0),X0	; Read from Y data memory
	JMP     <FINISH1	; Send out a header with the value
RDR	JCLR	#23,A,ERROR	; Test address bit for read from EEPROM memory
	BSET	#7,X:BCR	; Slow down P: accesses to EEPROM speed
	MOVE	X:<THREE,X0	; Convert to word address to a byte address
	MOVE	R0,Y0		; Get 16-bit address in a data register
	MPY	X0,Y0,A		; Multiply	
	ASR	A		; Eliminate zero fill of fractional multiply
	MOVE	A0,R0		; Need to address memory
	BSET	#15,R0		; Set bit so its in EEPROM space
	DO      #3,L1RDR
	MOVE    P:(R0)+,A2      ; Read each ROM byte
	REP     #8
	ASR     A               ; Move right into A1
	NOP
L1RDR
	MOVE    A1,X0           ; FINISH1 transmits X0 as its reply
	BCLR	#7,X:BCR	; Restore P: speed to fast
	JMP     <FINISH1

; Program WRMEM ('WRM' address datum): write to memory, reply 'DON'.
WRMEM	MOVE    X:(R4),R0	; Get the desired address
	MOVE	X:(R4)+,A	; We need a 24-bit version of the address
        MOVE    X:(R4)+,X0	; Get datum into X0 so MOVE works easily
        JCLR    #20,A,WRX	; Test address bit for Program memory
        MOVE	X0,P:(R0)	; Write to Program memory
        JMP     <FINISH
WRX     JCLR    #21,A,WRY	; Test address bit for X: memory
        MOVE    X0,X:(R0)	; Write to X: memory
        JMP     <FINISH
WRY     JCLR    #22,A,WRR	; Test address bit for Y: memory
        MOVE    X0,Y:(R0)	; Write to Y: memory
	JMP	<FINISH
WRR	JCLR	#23,A,ERROR	; Test address bit for write to EEPROM
	BSET	#7,X:BCR	; Slow down P: accesses to EEPROM speed
	MOVE	X:<THREE,X1	; Convert to word address to a byte address
	MOVE	R0,Y0		; Get 16-bit address in a data register
	MPY	X1,Y0,A		; Multiply	
	ASR	A		; Eliminate zero fill of fractional multiply
	MOVE	A0,R0		; Need to address memory
	BSET	#15,R0		; Set bit so its in EEPROM space
	MOVE    X0,A1           ; Get data from command string
	DO      #3,L1WRR	; Loop over three bytes of the word
	MOVE    A1,P:(R0)+      ; Write each EEPROM byte
	REP     #8
	ASR     A  X:<C50000,Y0 ; Move right one byte, enter delay
	DO      Y0,L2WRR	; Delay by 12 milliseconds for EEPROM write
	REP	#4		; Assume 50 MHz DSP56002
	NOP
L2WRR
	NOP                     ; DO loop nesting restriction
L1WRR
JMP_FIN	BCLR	#7,X:BCR	; Restore P: access speed
	JMP     <FINISH


; Read EEPROM code into DSP memory starting at P:APL_ADR. Allow $F00 bytes 
;    of EEPROM per application, from EEPROM address $0000 to $3FFF. Up to 
;    four applications can be loaded. The boot code starts at $4000.

LDAPPL	MOVE	X:(R4)+,X0		; Number of application program
	MOVE	X:<C780,Y0 		; $780 = $F00 / 2 because of MPY's LSHFT
	MPY	X0,Y0,A  #APL_ADR,R7
	MOVE	A0,R0			; EEPROM address = # x $F00
	BSET	#15,R0			; All EEPROM accesses => A15=1
	BSET	#7,X:BCR		; Slow down P: accesses to EEPROM speed
	DO	#MISC_LEN+APL_LEN,LD_LA2 ; Load from APL_ADR
	DO	#3,LD_LA1
	MOVE	P:(R0)+,A2		; Read from EEPROM
	REP	#8
	ASR	A
LD_LA1
	MOVE	A1,P:(R7)+		; Write to DSP P: memory
LD_LA2

; Splice the application and boot command tables together
	MOVE	#COM_TBL,R7		; Leave most of X: memory alone
	DO	#COM_LEN,LD_LA4 	; 32 commands, 2 DSP words per command
	DO	#3,LD_LA3
	MOVE	P:(R0)+,A2		; Read from EEPROM
	REP	#8
	ASR	A
LD_LA3
	MOVE	A1,X:(R7)+		; Write to DSP X: memory
LD_LA4

; Transfer to Y: memory, containing application program waveforms and 
;   readout parameters
	MOVE	#0,R7			; Start at bottom of Y: memory
	DO	#$500-APL_LEN-COM_LEN-MISC_LEN,LD_LA6
	DO	#3,LD_LA5
	MOVE	P:(R0)+,A2		; Read from EEPROM
	REP	#8
	ASR	A
LD_LA5
	MOVE	A1,Y:(R7)+		; Write to DSP Y: memory
LD_LA6
	JMP	<JMP_FIN		; Just to save one instruction

; Check that the boot code is not too big
        IF	@CVS(N,*)>APL_ADR
        WARN    'Boot program is too big!'	; Make sure application code
	ENDIF					;  will not be overwritten

;  ********* Beginning of X: definitions ************

; Status and header processing words
        ORG     X:0,P:LD_X
STATUS  DC      4       ; Status word; IDLEMODE bit is set

; Timer related constants
EXP_TIM DC      1000	; Exposure time (milliseconds), written by host computer
EL_TIM  DC      0       ; Elapsed exposure time in milliseconds
TGT_TIM DC      0	; TGT_TIM = EXP_TIM at beginning of exposure
SV_SR   DC      0       ; Save for timer ISR
SV_B0   DC      0       ; Save for timer ISR 
SV_B1   DC      0       ; Save for timer ISR 
SV_B2   DC      0       ; Save for timer ISR 
SV_Y1   DC      0       ; Save for timer ISR

LATCH	DC      $FA	; Starting value in latch chip U25
HDR	DC	0	; Header for all commands
NWORDS	DC	0	; Number of words in command
IDL_ADR	DC	0	; Address of routine to be executed when idle

; Miscellaneous constant definitions
ZERO    DC      0
ONE	DC	1
TWO	DC	2
THREE	DC	3
SEVEN	DC	7
EIGHT	DC	8
EN_SI	DC	$0160		; Enable the SSI serial port C
DISA_SI	DC	$0000		; Disable the SSI serial port C
C780	DC	$780		; EEPROM space per application program
C50000	DC	50000		; Delay for WRROM = 12 millisec
MASK1	DC	$FCFCF8		; Mask for checking header
MASK2	DC	$030300		; Mask for checking header
SBRD	DC	$020000 	; Source Identification number
DBRD	DC	$000200 	; Destination Identification number
DMASK   DC	$00FF00 	; Mask to get destination board number out
SMASK   DC	$FF0000 	; Mask to get source board number out
ERR	DC	'ERR'		; An error occurred
DON	DC	'DON'		; Command was fully processed
RXB      DC 'RXB'
TIM	DC	$020002		; Timing board reply header
UTL_REQ	DC	$555555		; Word for utility requesting SSI service
TIM_ACK	DC	$AAAAAA		; Word for timing acknowledging SSI service
TIM_COM	DC	4000		; Timing command timeout, about 2 milliseconds
SSI_HDR  DC $020003

; Command table resident in X: data memory
;   The first part of the command table will be loaded with application commands
	ORG     X:COM_TBL,P:COM_TBL+LD_X
	DC	0,START,0,START,0,START,0,START	; Space for 32 application 
	DC	0,START,0,START,0,START,0,START	;   commands
	DC	0,START,0,START,0,START,0,START
	DC	0,START,0,START,0,START,0,START
	DC	0,START,0,START,0,START,0,START
	DC	0,START,0,START,0,START,0,START
	DC	0,START,0,START,0,START,0,START
	DC	0,START,0,START,0,START,0,START
	DC      'TDL',TDL	; Test Data Link
	DC      'RDM',RDMEM	; Read from DSP or EEPROM memory         
	DC      'WRM',WRMEM	; Write to DSP memory        
	DC	'LDA',LDAPPL	; Load application progam from EEPROM to DSP
	DC      'STP',FINISH	; Put it here as a no op
	DC	'DON',PRC_RCV	; Nothing special
	DC      'ERR',PRC_RCV	; Nothing special
	DC	0,START		; Space for one more instruction

; End of program
	END
