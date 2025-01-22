       COMMENT *

This file is used to generate DSP code for the second generation 
timing boards to operate a HAWAII-I 1024x1024 pixel infrared array
at 3.0 microsec per pixel and whole frame readout. 
   **

   PAGE    132     ; Printronix page width - 132 columns

; Define a section name so it doesn't conflict with other application programs
   SECTION  RxTx_3

; Include a header file that defines global parameters
   INCLUDE  "HAWHead.asm"

APL_NUM  EQU   0 ; Application number from 0 to 3
CC       EQU   IRREV4+TIMREV4

;  Specify execution and load addresses
   IF    @SCP("CODE_TYPE","DOWNLOAD")
      ORG   P:APL_ADR,P:APL_ADR     ; Download address
   ELSE                             ; EEPROM address
      ORG   P:APL_ADR,P:APL_NUM*N_W_APL   
   ENDIF

;  Reset entire array and don't transmit any pixel data
RESET_ARRAY
   MOVE  #<READ_ON,R0               ; Turn Read ON 
   JSR   <CLOCK
   DO    Y:<N_RSTS,L_RESET
   MOVE  #<FRAME_INIT,R0
   JSR   <CLOCK
   DO    #256,END_FRAME
   MOVE  #<SHIFT_RESET_ODD_ROW,R0   ; Shift and reset the line
   JSR   <CLOCK
   MOVE  #<SHIFT_RESET_EVEN_ROW,R0  ; Shift and reset the line
   JSR   <CLOCK
   JSR   (R5)                       ; Check for incoming command if in continuous
   JCC   <NOT_COM                   ;  reset mode
   ENDDO                            ; If there is an incoming command then exit
   ENDDO                            ;  continuous mode and return
   JMP   <END_RST
NOT_COM  
   NOP
END_FRAME
   NOP
L_RESET
   NOP                              ; End of loop label for reading rows
END_RST
   MOVE  #<READ_OFF,R0              ; Turn Read OFF
   JSR   <CLOCK
   RTS

; Dummy subroutine to not call receiver checking routine
NO_CHK
   BCLR  #0,SR                      ; Clear status register clear bit
   RTS

;  ***********************   ARRAY READOUT   ********************
RD_ARRAY
   BSET  #ST_RDC,X:<STATUS          ; Set status to reading out
   JSR   <PCI_READ_IMAGE            ; Wake up the PCI interface board
   BSET  #WW,X:PBD                  ; Set WW = 1 for 16-bit image data
   JSET  #TST_IMG,X:STATUS,SYNTHETIC_IMAGE
   MOVE  #<READ_ON,R0               ; Turn Read ON and wait 5 milliseconds
   JSR   <CLOCK                     ;    so first few rows aren't at high
   DO    #598,DLY_ON                ;    count levels
   JSR   <PAL_DLY
   NOP
DLY_ON
   MOVE  #<FRAME_INIT,R0            ; Initialize the frame for readout
   JSR   <CLOCK
   DO    #256,FRAME
   MOVE  #<SHIFT_ODD_ROW,R0         ; Shift odd numbered rows
   JSR   <CLOCK
   MOVE  #<SHIFT_ODD_ROW_PIXELS,R0  ; Shift 2 columns, no transmit
   JSR   <CLOCK
   DO    #255,L_ODD_ROW
   MOVE  #<READ_ODD_ROW_PIXELS,R0   ; Read the pixels in odd rows
   JSR   <CLOCK
   NOP
L_ODD_ROW
   MOVE  #<SXMIT_EIGHT_PIXELS,R0    ; Series transmit last 8 pixels
   JSR   <CLOCK
   MOVE  #<SHIFT_EVEN_ROW,R0        ; Shift even numbered rows
   JSR   <CLOCK
   MOVE  #<SHIFT_EVEN_ROW_PIXELS,R0 ; Shift 2 columns, no transmit
   JSR   <CLOCK
   DO    #255,L_EVEN_ROW
   MOVE  #<READ_EVEN_ROW_PIXELS,R0  ; Read the pixels in even rows
   JSR   <CLOCK
   NOP
L_EVEN_ROW
   MOVE  #<SXMIT_EIGHT_PIXELS,R0    ; Series transmit last 8 pixels
   JSR   <CLOCK
   NOP
FRAME
   MOVE  #<READ_OFF,R0              ; Turn Read Off
   JSR   <CLOCK
RDA_END
   JSR   <PAL_DLY                   ; Wait for serial data transmission
   DO    #1500,*+3                  ; Delay for the PCI board to catch up
   NOP
   BCLR  #WW,X:PBD                  ; Clear WW to 0 for non-image data
   BCLR  #ST_RDC,X:<STATUS          ; Set status to reading out
   RTS


;  *********************  Acquire a complete image  **************************
; Reset array, wait, read it out n times, expose, read it out n times
START_EXPOSURE
   MOVEP #$020102,Y:WRFO            ; Send header word to the FO transmitter
   REP   #15                        ; Delay a bit for the fiber optics to transmit
   NOP
   MOVEP #'IIA',Y:WRFO
   REP   #15                        ; Delay a bit for the fiber optics to transmit
   NOP
   JSR   <READING_IMAGE_ON
   MOVE  #NO_CHK,R5                 ; Don't check for incoming commands
   JSR   <RESET_ARRAY               ; Reset the array twice
   JSR   <SHORT_DELAY               ; Call short delay for reset to settle down
   DO    Y:<N_RA,L_MRA1             ; Read N_RA times
   JSR   <RD_ARRAY                  ; Call read array subroutine
   NOP
L_MRA1
   MOVE  #L_MRA2,R7
   JMP   <EXPOSE                    ; Delay for specified exposure time
L_MRA2
   DO    Y:<N_RA,L_MRA3             ; Read N_RA times again
   JSR   <RD_ARRAY                  ; Call read array subroutine
   NOP
L_MRA3
   JMP   <START                     ; This is the end of the exposure

;  *************************    SUBROUTINE    ***********************
;  Core subroutine for clocking out array charge
CLOCK
   MOVE  Y:(R0)+,X0                 ; # of waveform entries 
   MOVE  Y:(R0)+,A                  ; Start the pipeline
   DO    X0,CLK1                    ; Repeat X0 times
   MOVE  A,X:(R6) Y:(R0)+,A         ; Send out the waveform
CLK1
   MOVE  A,X:(R6)                   ; Flush out the pipeline
   RTS                              ; Return from subroutine

;  ****************  PROGRAM CODE IN SRAM PROGRAM SPACE    *******************
; Put all the following code in SRAM, starting at P:$200.
   IF    @SCP("CODE_TYPE","DOWNLOAD")
      ORG   P:$200,P:$200           ; Download address
   ELSE                             ; ROM address
      ORG   P:$200,P:APL_NUM*N_W_APL+APL_LEN 
   ENDIF

; Set software to video mode #1
VD1
   MOVE  #VIDEO_MODE1,X0
   MOVE  X0,X:<IDL_ADR
   JMP   <FINISH                    ; Send reply

; Set software to video mode #2
VD2
   MOVE  #VIDEO_MODE2,X0
   MOVE  X0,X:<IDL_ADR
   JMP   <FINISH                    ; Send reply

; Exit video mode, enter continuous reset mode
STOP_VIDEO
   MOVE  #CONT_RST,X0
   MOVE  X0,X:<IDL_ADR
   JMP   <FINISH

; Video mode #1 - reset, integrate, read, ad infinitum
VIDEO_MODE1
   MOVE  #NO_CHK,R5                 ; Don't process incoming commands
   JSR   <READING_IMAGE_ON
   JSR   <RESET_ARRAY               ; Reset the array
   JSR   <READING_IMAGE_OFF
   MOVE  #L_VID1,R7                 ; Return address after exposure
   JMP   <EXPOSE                    ; Delay for specified exposure time
L_VID1
   JSR   <RD_ARRAY                  ; Read the array
   JSR   <GET_RCV                   ; Look for a new command
   JCS   <CHK_SSI                   ; If none, then stay in video mode
   JMP   <VIDEO_MODE1

; Video mode #2 - reset, short delay, read, integrate, read, ad infinitum
VIDEO_MODE2
   MOVE  #NO_CHK,R5                 ; Don't process incoming commands
   JSR   <READING_IMAGE_ON
   JSR   <RESET_ARRAY               ; Reset the array
   JSR   <SHORT_DELAY               ; Call short delay for reset to settle down
   JSR   <RD_ARRAY                  ; Read the array
   MOVE  #L_VID2,R7                 ; Return address after exposure
   JMP   <EXPOSE                    ; Delay for specified exposure time
L_VID2
   JSR   <RD_ARRAY                  ; Read the array
   JSR   <GET_RCV                   ; Look for a new command
   JCS   <CHK_SSI                   ; If none, then stay in video mode
   JMP   <VIDEO_MODE2

; Continuously reset array, checking for host commands every line
CONT_RST
   MOVE  #<GET_RCV,R5               ; Check for commands every line
   JSR   <RESET_ARRAY               ; Reset the array once
   JCS   <CHK_SSI                   ; If there's a command check its header
   JMP   <CONT_RST                  ; If there is no command, keep resetting

; Short delay for the array to settle down after a global reset
SHORT_DELAY
   MOVE  Y:<RST_DLY,A               ; Enter reset delay into timer
CON_DELAY                           ; Alternate entry for camera on delay
   MOVE  A,X:<TGT_TIM
   CLR   A                          ; Zero out elapsed time
   MOVE  A,X:<EL_TIM
   BSET  #0,X:TCSR                  ; Enable DSP timer
CNT_DWN
   JSET  #0,X:TCSR,CNT_DWN          ; Wait here for timer to count down
   RTS

; Abort exposure and stop the timer
ABR_EXP
   CLR   A                          ; Just stop the timer
   MOVE  A,X:<TGT_TIM
   JMP   <FINISH                    ; Send normal reply

; Set number of readout pairs in multiple readout mode
SET_NUM_READS
   MOVE  X:(R4)+,X0
   MOVE  X0,Y:<N_RA
   JMP   <FINISH

; Set the exposure time
SET_EXT
   MOVE  X:(R4)+,A                  ; Get third word of command = exposure time
   MOVE  #>5,X0                     ; Subtract 5 millisec from exposure time to
   SUB   X0,A                       ;   account for READ to FSYNC delay time
   MOVE  A,X:<EXP_TIM               ; Write to magic address
   MOVE  A,X:<TGT_TIM
   JMP   <FINISH                    ; Send out 'DON' reply

; Read the elapsed exposure time
RD_EXT
   MOVE  X:<EL_TIM,X0               ; Read elapsed exposure time
   JMP   <FINISH1                   ; Send out time in milliseconds

;  Update the DACs
SET_DAC
   DO    Y:(R0)+,SET_L0             ; Repeat X0 times
   MOVEP Y:(R0)+,X:SSITX            ; Send out the waveform
   JSR   <PAL_DLY                   ; Wait for SSI and PAL to be empty
   NOP                              ; Do loop restriction
SET_L0
   RTS                              ; Return from subroutine

; Delay for serial writes to the PALs and DACs by 8 microsec
PAL_DLY
   DO    #150,DLY                   ; Wait 8 usec for serial data transmission
   NOP
DLY
   NOP
   RTS

; Enable serial communication to the analog boards
SER_ANA
   MOVEP #$0000,X:PCC               ; Software reset of SSI
   BCLR  #10,X:CRB                  ; Change SSI to continuous clock for analog
   MOVEP #$0163,X:PCC               ; Re-enable the SSI
   BSET  #0,X:PBD                   ; Set H0 for analog boards SSI
   RTS

; Enable serial communication to the utility board
SER_UTL
   MOVEP #$0000,X:PCC               ; Software reset of SSI
   BSET  #10,X:CRB                  ; Change SSI to gated clock for utility board 
   MOVEP #$0163,X:PCC               ; Enable the SSI
   BCLR  #0,X:PBD                   ; Clear H0 for utility board SSI
   RTS

; Let the host computer read the controller configuration
READ_CONTROLLER_CONFIGURATION
   MOVE  Y:<CONFIG,X0               ; Just transmit the configuration
   JMP   <FINISH1

; Set a voltage or video processor offset.
;
; Command syntax is  SBN  #video_board  #DAC_number 'type of board' #voltage
;                       #video_board is from 0 to 15
;                       #DAC_number is from 0 to 15
;                       'type of board' is 'CLK' or 'VID'
;                       #voltage is from 0 to 4095

SET_BIAS_NUMBER                     ; Set bias number
   JSR   <SER_ANA                   ; Enable the SSI for analog boards
   MOVE  X:(R4)+,A                  ; First argument is board number, 0 to 15
   REP   #20
   LSL   A
   MOVE  A,X0
   MOVE  X:(R4)+,A                  ; Second argument is DAC number, 0 to 15
   REP   #14
   LSL   A
   OR    X0,A
   MOVE  X:(R4)+,B                  ; Third argument is 'VID' or 'CLK' string
   MOVE  #'VID',X0
   CMP   X0,B
   JNE   <CLK_DRV
   BSET  #19,A1                     ; Set bits to mean video processor DAC
   BSET  #18,A1
   JMP   <VID_BRD
CLK_DRV
   MOVE  #'CLK',X0
   CMP   X0,B
   JNE   <ERR_SBN
VID_BRD
   MOVE  A,X0
   MOVE  X:(R4)+,A                  ; Fourth argument is voltage value, 0 to $fff
   MOVE  #$000FFF,Y0                ; Mask off just 12 bits to be sure
   AND   Y0,A
   OR    X0,A
   MOVEP A,X:SSITX                  ; Write the number to the DAC
   JSR   <PAL_DLY                   ; Wait for the number to be sent
   JSR   <SER_UTL                   ; Enable the SSI for the utility board
   JMP   <FINISH
ERR_SBN
   MOVE  X:(R4)+,A                  ; Read and discard the fourth argument
   JSR   <SER_UTL                   ; Enable the SSI for the utility board
   JMP   <ERROR

; This is where the pixel clock is selected for the diagnostic jack 
;    on the clock driver board 
; 
; Specify the MUX value to be output on the clock driver board
; Command syntax is  SMX  #clock_driver_board #MUX1 #MUX2
;                 #clock_driver_board from 0 to 15
;                 #MUX1, #MUX2 from 0 to 23
SET_MUX
   JSR   <SER_ANA                   ; Set SSI to analog board communication
   MOVE  X:(R4)+,A                  ; Clock driver board number
   REP   #20
   LSL   A
   MOVE  #$003000,X0
   OR    X0,A
   MOVE  A,X1                       ; Move here for storage
   MOVE  X:(R4)+,A                  ; Get the first MUX number
   JLT   ERR_SM1
   MOVE  #>24,X0                    ; Check for argument less than 32
   CMP   X0,A
   JGE   ERR_SM1
   MOVE  A,B
   MOVE  #>7,X0
   AND   X0,B
   MOVE  #>$18,X0
   AND   X0,A
   JNE   <SMX_1                     ; Test for 0 <= MUX number <= 7
   BSET  #3,B1
   JMP   <SMX_A
SMX_1
   MOVE  #>$08,X0
   CMP   X0,A                       ; Test for 8 <= MUX number <= 15
   JNE   <SMX_2
   BSET  #4,B1
   JMP   <SMX_A
SMX_2
   MOVE  #>$10,X0
   CMP   X0,A                       ; Test for 16 <= MUX number <= 23
   JNE   <ERR_SM1
   BSET  #5,B1
SMX_A
   OR    X1,B1                      ; Add prefix to MUX numbers
   MOVE  B1,Y1
   MOVE  X:(R4)+,A                  ; Get the next MUX number
   JLT   ERR_SM2
   MOVE  #>24,X0                    ; Check for argument less than 32
   CMP   X0,A
   JGE   ERR_SM2
   REP   #6
   LSL   A
   MOVE  A,B
   MOVE  #$1C0,X0
   AND   X0,B
   MOVE  #>$600,X0
   AND   X0,A
   JNE   <SMX_3                     ; Test for 0 <= MUX number <= 7
   BSET  #9,B1
   JMP   <SMX_B
SMX_3
   MOVE  #>$200,X0
   CMP   X0,A                       ; Test for 8 <= MUX number <= 15
   JNE   <SMX_4
   BSET  #10,B1
   JMP   <SMX_B
SMX_4
   MOVE  #>$400,X0
   CMP   X0,A                       ; Test for 16 <= MUX number <= 23
   JNE   <ERR_SM2
   BSET  #11,B1
SMX_B
   ADD   Y1,B                       ; Add prefix to MUX numbers
   MOVEP B1,X:SSITX
   JSR   <PAL_DLY                   ; Delay for all this to happen
   JSR   <SER_UTL                   ; Return SSI to utility board communication
   JMP   <FINISH
ERR_SM1
   MOVE  X:(R4)+,A
ERR_SM2
   JSR   <SER_UTL                   ; Return SSI to utility board communication
   JMP   <ERROR

; Write an arbitraty control word over the SSI link to any register, any board
; Command syntax is  WRC number, number is 24-bit number to be sent to any board
WR_CNTRL
   JSR   <SER_ANA                   ; Set SSI to analog board communication
   JSR   <PAL_DLY                   ; Wait for the number to be sent
   MOVEP X:(R4)+,X:SSITX            ; Send out the waveform
   JSR   <PAL_DLY                   ; Wait for SSI and PAL to be empty
   JSR   <SER_UTL                   ; Return SSI to utility board communication
   JMP   <FINISH

; Power off
PWR_OFF
   JSR   <SER_ANA                   ; Enable the SSI for analog boards
   BCLR  #CDAC,X:<LATCH             ; Clear all DACs
   BCLR  #ENCK,X:<LATCH             ; Disable DAC output switches
   MOVEP X:LATCH,Y:WRLATCH
   BSET  #LVEN,X:PBD                ; LVEN = HVEN = 1 => Power reset
   BSET  #HVEN,X:PBD                ; timFO value
   MOVE  #TST_RCV,X0
   MOVE  X0,X:<IDL_ADR
   JSR   <SER_UTL                   ; Enable the SSI for the utility board
   JMP   <FINISH

; Start power-on cycle
PWR_ON
   JSR   <SER_ANA                   ; Enable the SSI for analog boards
   BSET  #CDAC,X:<LATCH             ; Disable clearing of all DACs
   BCLR  #ENCK,X:<LATCH             ; Disable DAC output switches
   MOVEP X:LATCH,Y:WRLATCH
                                    ; Turn analog power on to controller boards, 
                                    ;  but not yet to IR array
   BSET  #LVEN,X:PBD                ; LVEN = HVEN = 1 => Power reset
   BSET  #HVEN,X:PBD
                                    ; Now ramp up the low voltages (+/- 6.5V, 16.5V)
                                    ;  and delay them to turn on
   BCLR  #LVEN,X:PBD                ; LVEN = Low => Turn on +/- 6.5V, 
   MOVE  Y:<PWR_DLY,A               ;   +/- 16.5V
   JSR   <CON_DELAY
                                    ; Zero all voltages and enable DAC switches
   MOVE  #<ZERO_BIASES,R0           ; Get starting address of DAC values
   JSR   <SET_DAC
   MOVE  X:<THREE,A
   JSR   <CON_DELAY
   BSET  #ENCK,X:<LATCH             ; Enable clock and DAC output switches
   MOVEP X:LATCH,Y:WRLATCH          ; Disable DAC clearing, enable clocks
                                    ; Turn on Vdd = digital power UC to the IR array
   MOVEP Y:VDD,X:SSITX              ; pin #5 = Vdd = digital power on array
   MOVE  Y:<VDD_DLY,A               ; Delay for the IR array to settle
   JSR   <CON_DELAY
SETBIAS                             ; Set DC bias DACs
   JSR   <SER_ANA                   ; Enable the SSI for analog boards
   JSR   <PAL_DLY                   ; Wait for port to be enabled
   MOVE  #<DC_BIASES,R0             ; Get starting address of DAC values
   JSR   <SET_DAC
   MOVE  X:<THREE,A                 ; Delay three millisec to settle
   JSR   <CON_DELAY
                                    ; Set clock driver DACs
   MOVE  #<DACS,R0                  ; Get starting address of DAC values
   JSR   <SET_DAC
                                    ; Continuous reset mode on, disable SSI, & return 
   MOVE  #CONT_RST,X0
   MOVE  X0,X:<IDL_ADR
   JSR   <SER_UTL                   ; Enable the SSI for the utility board
   JMP   <FINISH
                                    
   
SYNTHETIC_IMAGE                     ; Generate a synthetic image by simply 
   CLR   A                          ;  incrementing the pixel counts
   MOVE  A,Y:<TST_DAT
   DO    #1024,LPR_TST              ; Loop over each line readout
   DO    #1024,LSR_TST              ; Loop over number of pixels per line
   REP   #20                        ; #20 => 1.0 microsec per pixel
   NOP
   MOVE  X:<ONE,X1                  ; Increment pixel counts by one
   MOVE  Y:<TST_DAT,A
   ADD   X1,A                       ; Pixel data = Y:TST_DAT = Y:TST_DAT + 1
   MOVE  A,Y:<TST_DAT
   MOVEP A,Y:WRFO                   ; Transmit to fiber optic	
LSR_TST
   NOP
LPR_TST
   JMP   <RDA_END                   ; Normal exit

PCI_READ_IMAGE                      ; Alert the PCI board that images are coming soon
   MOVEP #$020104,Y:WRFO            ; Send header word to the FO transmitter
   REP   #15                        ;  Delay a bit for the transmission
   NOP
   MOVEP #'RDA',Y:WRFO
   REP   #15
   NOP
   MOVEP #1024,Y:WRFO               ; Number of columns to read
;   MOVEP #512,Y:WRFO                ; Number of columns to read
   REP   #15
   NOP
   MOVEP #1024,Y:WRFO               ; Number of rows to read
;   MOVEP #512,Y:WRFO                ; Number of rows to read
   REP   #15
   NOP
   RTS

READING_IMAGE_ON                    ; Put PCI board in reading image out mode to 
                                    ;  block commands to the timing board
   MOVEP #$020102,Y:WRFO            ; Send header word to the FO transmitter
   REP   #15                        ; Delay a bit for the transmission
   NOP
   MOVEP #'RDI',Y:WRFO
   REP   #15
   NOP
   RTS

READING_IMAGE_OFF                   ; Restore PCI board to normally processing comamnds
   MOVEP #$020102,Y:WRFO            ; Send header word to the FO transmitter
   REP   #15                        ; Delay a bit for the transmission
   NOP
   MOVEP #'RDO',Y:WRFO
   REP   #15
   NOP
   RTS

TEST_BYTE_BUFFER                    ; Test byte buffering
   MOVEP X:SSI_HDR,Y:WRFO           ; Send word to the FO transmitter
   REP   #40                        ; Delay a bit for the FO
   NOP
   MOVEP X:RXB,Y:WRFO               ; Transmit 'RXB' command	
   REP   #40                        ; Delay a bit for the FO
   NOP
   MOVEP X:(R4)+,Y:WRFO             ; Read and transmit the SCI byte
   JMP   <START                     ; Return from interrupt service

; Command table - make sure there are exactly 32 entries in it
   IF    @SCP("CODE_TYPE","DOWNLOAD")
      ORG   X:COM_TBL,X:COM_TBL     ; Download address
   ELSE                             ; EEPROM address
      ORG   P:COM_TBL,P:APL_NUM*N_W_APL+APL_LEN+MISC_LEN
   ENDIF

   DC 'SEX',START_EXPOSURE          ; Start exposure
   DC 'SNR',SET_NUM_READS           ; Multiple reads of array
   DC 'AEX',ABR_EXP                 ; End current exposure
   DC 'PON',PWR_ON                  ; Turn on analog power
   DC 'POF',PWR_OFF                 ; Turn off analog power
   DC 'SET',SET_EXT                 ; Set exposure time
   DC 'RET',RD_EXT                  ; Read elapsed time
   DC 'SBN',SET_BIAS_NUMBER         ; Set bias number
   DC 'SMX',SET_MUX                 ; Select MUX output to diagnostic coax
   DC 'SBV',SETBIAS                 ; Set DC bias supply voltages
   DC 'WRC',WR_CNTRL                ; Write a word to the SSI
   DC 'VD1',VD1                     ; Put array in video #1 mode    
   DC 'VD2',VD2                     ; Put array in video #2 mode    
   DC 'STP',STOP_VIDEO              ; Exit video mode
   DC 'RCC',READ_CONTROLLER_CONFIGURATION 
   DC 'DON',START                   ; Nothing special
   DC 'TBB',TEST_BYTE_BUFFER
   DC 0,START,0,START,0,START,0,START
   DC 0,START,0,START,0,START,0,START
   DC 0,START,0,START,0,START,0,START
   DC 0,START,0,START,0,START
   
   IF    @SCP("DOWNLOAD","HOST")    ; Download address
      ORG   Y:0,Y:0
   ELSE                             ; EEPROM address continues from P: above
      ORG   Y:0,P:
   ENDIF

DUMMY    DC 0                       ; Left over from previous versions
NCOLS    DC 255                     ; Number of columns (not used)
NROWS    DC 256                     ; Number of rows (not used)
N_RA     DC 1                       ; Desired number of reset/read pairs
RST_DLY  DC 50                      ; Delay after array reset for settling
PWR_DLY  DC 100                     ; Delay in millisec for power to turn on
VDD_DLY  DC 300                     ; Delay in millisec for VDD to settle   
N_RSTS   DC 2                       ; Number of resets
CONFIG   DC CC                      ; Controller configuration
TST_DAT  DC 0                       ; Test image data for synthetic images

; Start the voltage and timing tables at a fixed address
   IF    @SCP("CODE_TYPE","DOWNLOAD")
      ORG   Y:TBL_ADR,Y:TBL_ADR     ; Download address
   ELSE                             ; EEPROM address
      ORG   Y:TBL_ADR,P:APL_NUM*N_W_APL+APL_LEN+MISC_LEN+$4F
   ENDIF

; Miscellaneous definitions
VIDEO    EQU   $000000              ; Video board select = 0 for first A/D board
CLK2     EQU   $002000              ; Clock board select = 2 
DELAY    EQU   $480000              ; Dly for clking, (20 nsec/unit, 160 nsec if MSB set)
VP_DLY   EQU   $2C0000              ; Video delay time for 3 microsec/pixel

   IF    @SCP("OUTPUTS","1")
SXMIT    EQU $00F000                ; Series transmit A/D channels #0 only
   ELSE
SXMIT    EQU $00F060                ; Series transmit A/D channels #0-#3
   ENDIF

;  Clock voltage definitions
CLK_HIGH EQU   $CC0                 ; +4V, assuming +VREF = +2.5
CLK_LOW  EQU   $0F4                 ; +.30V, assuming -VREF =  0.0

; Table of offset values begins at Y:$10

; DAC settings for the video offsets
DC_BIASES   DC ZERO_BIASES-DC_BIASES-1
OFF_0       DC $0c0000              ; Input offset board #0, channel A
OFF_1       DC $0c4000              ; Input offset board #0, channel B
OFF_2       DC $1c0000              ; Input offset board #1, channel A
OFF_3       DC $1c4000              ; Input offset board #1, channel B

; DAC settings to generate DC bias voltages for the PICNIC array
VOFFSET     DC $0c8bd4              ; pin #1 = preamp offset = +3.7 volts
VRESET      DC $0cc195              ; pin #2 = reset = +0.5 volts
VD          DC $0d0fff              ; pin #3 = analog power = +5.0 volts
ICTL        DC $0d4bd4              ; pin #4 = current control = +3.7 volts
VDD         DC $0d8ccb              ; pin #5 = digital power = +4.0 volts  
VUNUSED     DC $0dc000              ; pin #6 = unused to 0V

;  Zero out the DC biases during the power-on sequence
ZERO_BIASES
   DC DACS-ZERO_BIASES-1
   DC $0c8000                       ; Pin #1, board #0
   DC $0cc000                       ; Pin #2
   DC $0d0000                       ; Pin #3
   DC $0d4000                       ; Pin #4
   DC $0d8000                       ; Pin #5
   DC $0dc000                       ; Pin #6
   DC $1c8000                       ; Pin #1, board #1
   DC $1cc000                       ; Pin #2
   DC $1d0000                       ; Pin #3
   DC $1d4000                       ; Pin #4
   DC $1d8000                       ; Pin #5
   DC $1dc000                       ; Pin #6

; Initialize all DACs, starting with the clock driver ones
DACS
   DC READ_ON-DACS-1
   DC (CLK2<<8)+(0<<14)+CLK_HIGH    ; Pin #1, RESET
   DC (CLK2<<8)+(1<<14)+CLK_LOW
   DC (CLK2<<8)+(2<<14)+CLK_HIGH    ; Pin #2, LINE
   DC (CLK2<<8)+(3<<14)+CLK_LOW
   DC (CLK2<<8)+(4<<14)+CLK_HIGH    ; Pin #3, LSYNC
   DC (CLK2<<8)+(5<<14)+CLK_LOW
   DC (CLK2<<8)+(6<<14)+CLK_HIGH    ; Pin #4, FSYNC
   DC (CLK2<<8)+(7<<14)+CLK_LOW
   DC (CLK2<<8)+(8<<14)+CLK_HIGH    ; Pin #5, PIXEL
   DC (CLK2<<8)+(9<<14)+CLK_LOW
   DC (CLK2<<8)+(10<<14)+CLK_HIGH   ; Pin #6, READ
   DC (CLK2<<8)+(11<<14)+CLK_LOW
   DC (CLK2<<8)+(12<<14)            ; Pin #7, not connected=0 volts
   DC (CLK2<<8)+(13<<14)
   DC (CLK2<<8)+(14<<14)            ; Pin #8, not connected=0 volts
   DC (CLK2<<8)+(15<<14)

; Define switch state bits for the clocks
L_RST   EQU 0    
H_RST   EQU 1
L_LINE  EQU 0
H_LINE  EQU 2
L_LSYNC EQU 0     
H_LSYNC EQU 4
L_FSYNC EQU 0
H_FSYNC EQU 8
L_PIXEL EQU 0
H_PIXEL EQU $10
L_READ  EQU 0
H_READ  EQU $20

READ_ON                             ; Turn READ ON for readout and reset
   DC READ_OFF-READ_ON-2
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY

READ_OFF                            ; Turn READ OFF during exposure
   DC SHIFT_RESET_ODD_ROW-READ_OFF-2
   DC CLK2+L_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+L_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY

SHIFT_RESET_ODD_ROW                 ; Shift and reset the odd numbered lines
   DC SHIFT_RESET_EVEN_ROW-SHIFT_RESET_ODD_ROW-2
   DC CLK2+H_READ+L_PIXEL+L_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+L_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY

SHIFT_RESET_EVEN_ROW                ; Shift and reset the even numbered lines
   DC FRAME_INIT-SHIFT_RESET_EVEN_ROW-2
   DC CLK2+H_READ+L_PIXEL+L_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+L_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY

FRAME_INIT                          ; Initialize the frame for readout
   DC SHIFT_ODD_ROW-FRAME_INIT-2
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+L_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+L_LSYNC+L_LINE+L_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+L_LSYNC+L_LINE+H_FSYNC+H_RST

SHIFT_ODD_ROW
   DC READ_ODD_ROW_PIXELS-SHIFT_ODD_ROW-2
   DC CLK2+H_READ+L_PIXEL+L_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+$900000
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+$7C0000

READ_ODD_ROW_PIXELS
   DC SHIFT_ODD_ROW_PIXELS-READ_ODD_ROW_PIXELS-2
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit four pixels' data
   DC $140033                       ; Delay
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit four pixels' data
   
SHIFT_ODD_ROW_PIXELS
   DC SHIFT_EVEN_ROW-SHIFT_ODD_ROW_PIXELS-2
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC $160033                       ; Padding
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC $000033                       ; Padding

SHIFT_EVEN_ROW
   DC READ_EVEN_ROW_PIXELS-SHIFT_EVEN_ROW-2
   DC CLK2+H_READ+L_PIXEL+L_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+$900000
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+$7C0000

READ_EVEN_ROW_PIXELS
   DC SHIFT_EVEN_ROW_PIXELS-READ_EVEN_ROW_PIXELS-2
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit four pixels' data
   DC $140033                       ; Delay
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit four pixels' data

SHIFT_EVEN_ROW_PIXELS
   DC SXMIT_EIGHT_PIXELS-SHIFT_EVEN_ROW_PIXELS-2
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC $160033                       ; Padding
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC $000033                       ; Padding

SXMIT_EIGHT_PIXELS
   DC END_TBL-SXMIT_EIGHT_PIXELS-2
   DC DELAY+$000033
   DC VP_DLY                        ; A/D sample
   DC $000033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit four pixels' data
   DC DELAY+$000033
   DC VP_DLY                        ; A/D sample
   DC $000033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit four pixels' data

END_TBL  DC 0                       ; End of waveform tables

   ENDSEC                           ; End of section RxTx_3

   END                              ; End of program

