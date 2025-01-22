         COMMENT *

This file is used to generate DSP code for the second generation 
timing boards to operate a HAWAII-I 1024x1024 pixel infrared 
array at 3.0 microsec per pixel with single subarray readout. 
   **

   PAGE     132                     ; Printronix page width - 132 columns

; Define a section name so it doesn't conflict with other application programs
   SECTION  SUBARRAY   
   
; Include a header file that defines global parameters
   INCLUDE  "HAWHead.asm"

APL_NUM  EQU 1                      ; Application number from 0 to 3
CC       EQU IRREV4+TIMREV4

;  Specify execution and load addresses
   IF    @SCP("DOWNLOAD","HOST")    ; Download address
      ORG   P:APL_ADR,P:APL_ADR
   ELSE                             ; EEPROM address
      ORG   P:APL_ADR,P:APL_NUM*N_W_APL 
   ENDIF

;  Reset entire array, line by line, don't transmit any pixel data
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

; Calculate number of columns to read out minus 1  
   MOVE  Y:<NCOLS,A
   LSR   A
   MOVE  X:<ONE,X0
   SUB   X0,A
   MOVE  A,Y:<NCOLS_DIV_2_MINUS_1
   MOVE  Y:<NROWS,A
   LSR   A                          ; /2 for CDS
   LSR   A                          ; /2 for odd/even readout
   MOVE  A,Y:<NROWS_DIV_2

; COL_SKP = COL_OFFSET / 2 or COL_SKP = 1 if COL_OFFSET = 0
   MOVE  Y:<COL_OFFSET,A
   TST   A
   JEQ   <SET_SKP
   LSR   A  
   JMP   <SKIP
SET_SKP
   MOVE  X:<ONE,A
SKIP
   MOVE  A,Y:<COL_SKP
   BSET  #WW,X:PBD                  ; Set WW to 1 for 16-bit image data
   MOVE  #<READ_ON,R0               ; Turn Read ON and wait 5 milliseconds
   JSR   <CLOCK                     ;    so first few rows aren't at high
   DO    #598,DLY_ON                ;    count levels
   JSR   <PAL_DLY
   NOP
DLY_ON
   MOVE  #<FRAME_INIT,R0            ; Initialize the frame for readout
   JSR   <CLOCK

; Subarray readout, by skipping first ROW_OFFSET rows
   MOVE  Y:<ROW_OFFSET,A
   TST   A
   JEQ   NO_SKIP
   LSR   A                          ; /2 => Two rows skipped per DO loop
   DO    A,L_ROW_SKIP
   MOVE  #<SHIFT_ODD_ROW,R0
   JSR   <CLOCK
   MOVE  #<SHIFT_EVEN_ROW,R0
   JSR   <CLOCK
   NOP
L_ROW_SKIP
NO_SKIP
   DO    Y:<NROWS_DIV_2,FRAME

; First shift and read the odd numbered rows
   MOVE  #<SHIFT_ODD_ROW,R0         ; Shift odd numbered rows
   JSR   <CLOCK
   DO    Y:<COL_SKP,L_COL_SKIP_ODD
   MOVE  #<SHIFT_ODD_ROW_PIXELS,R0  ; Shift columns, no transmit
   NOP
   MOVE  Y:(R0)+,X0                 ; # of waveform entries 
   MOVE  Y:(R0)+,A                  ; Start the pipeline
   REP   X0                         ; Repeat X0 times
   MOVE  A,X:(R6) Y:(R0)+,A         ; Send out the waveform
   MOVE  A,X:(R6)                   ; Flush out the pipeline
L_COL_SKIP_ODD
   DO    Y:<NCOLS_DIV_2_MINUS_1,L_ODD_ROW
   MOVE  #<READ_ODD_ROW_PIXELS,R0   ; Read the pixels in odd rows
   NOP
   MOVE  Y:(R0)+,X0                 ; # of waveform entries 
   MOVE  Y:(R0)+,A                  ; Start the pipeline
   REP   X0                         ; Repeat X0 times
   MOVE  A,X:(R6) Y:(R0)+,A         ; Send out the waveform
   MOVE  A,X:(R6)                   ; Flush out the pipeline
L_ODD_ROW
   MOVE  #<SXMIT_TWO_PIXELS,R0      ; Series transmit last 2 pixels
   JSR   <CLOCK

; Then shift and read the even numbered rows
   MOVE  #<SHIFT_EVEN_ROW,R0        ; Shift even numbered rows
   JSR   <CLOCK
   DO    Y:<COL_SKP,L_COL_SKIP_EVEN
   MOVE  #<SHIFT_EVEN_ROW_PIXELS,R0 ; Shift 2 columns, no transmit
   NOP
   MOVE  Y:(R0)+,X0                 ; # of waveform entries 
   MOVE  Y:(R0)+,A                  ; Start the pipeline
   REP   X0                         ; Repeat X0 times
   MOVE  A,X:(R6) Y:(R0)+,A         ; Send out the waveform
   MOVE  A,X:(R6)                   ; Flush out the pipeline
L_COL_SKIP_EVEN
   DO    Y:<NCOLS_DIV_2_MINUS_1,L_EVEN_ROW
   MOVE  #<READ_EVEN_ROW_PIXELS,R0  ; Read the pixels in even rows
   NOP
   MOVE  Y:(R0)+,X0                 ; # of waveform entries 
   MOVE  Y:(R0)+,A                  ; Start the pipeline
   REP   X0                         ; Repeat X0 times
   MOVE  A,X:(R6) Y:(R0)+,A         ; Send out the waveform
   MOVE  A,X:(R6)                   ; Flush out the pipeline
L_EVEN_ROW
   MOVE  #<SXMIT_TWO_PIXELS,R0      ; Series transmit last 2 pixels
   JSR   <CLOCK
   NOP
FRAME

RDA_END
   MOVE  #<READ_OFF,R0              ; Turn Read Off
   JSR   <CLOCK
   JSR   <PAL_DLY                   ; Wait for serial data transmission
   BCLR  #ST_RDC,X:<STATUS          ; Set status to reading out
   BCLR  #WW,X:PBD                  ; Clear WW to 0 for non-image data
   RTS


;  *********************  Acquire a complete image  **************************
; Reset array, wait, read it out, expose, read it out again
START_EXPOSURE
   MOVE  #$020102,X0
   JSR   <XMT_FO
   MOVE  #'IIA',X0
   JSR   <XMT_FO
   JSR   <READING_IMAGE_ON
   MOVE  #NO_CHK,R5                 ; Don't check for incoming commands
   JSR   <RESET_ARRAY               ; Reset the array twice
   JSR   <SHORT_DELAY               ; Call short delay for reset to settle down
   JSR   <READING_IMAGE_OFF
   JSR   <RD_ARRAY                  ; Call read array subroutine
   MOVE  #L_MRA2,R7
   JMP   <EXPOSE                    ; Delay for specified exposure time
L_MRA2   
   JSR   <RD_ARRAY                  ; Call read array subroutine
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
   IF    @SCP("DOWNLOAD","HOST")    ; Download address
      ORG   P:$200,P:$200  
   ELSE                             ; ROM address
      ORG   P:$200,P:APL_NUM*N_W_APL+APL_LEN 
   ENDIF

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

; Set the exposure time
SET_EXT
   MOVE  X:(R4)+,A                  ; Get third word of command = exposure time
   MOVE  #>5,X0                     ; Subtract 5 millisec from exposure time to 
   SUB   X0,A                       ;   account for READ to FSYNC delay time
   MOVE  A,X:<EXP_TIM               ; Write to magic address
   MOVE  A,X:<TGT_TIM
   JMP   <FINISH                    ; Send out 'DON' reply

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
   MOVEP #$0160,X:PCC               ; Re-enable the SSI
   BSET  #0,X:PBD                   ; Set H0 for analog boards SSI
   RTS

; Let the host computer read the controller configuration
READ_CONTROLLER_CONFIGURATION
   MOVE  Y:<CONFIG,X0               ; Just transmit the configuration
   JMP   <FINISH1

; Set a voltage or video processor offset.
;
; Command syntax is  SBN  #video_board  #DAC_number 'type of board' #voltage
;           #video_board is from 0 to 15
;           #DAC_number is from 0 to 15
;           'type of board' is 'CLK' or 'VID'
;           #voltage is from 0 to 4095

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
   JMP   <FINISH
ERR_SBN
   MOVE  X:(R4)+,A                  ; Read and discard the fourth argument
   JMP   <ERROR

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
   JMP   <FINISH

; Start power-on cycle
PWR_ON
   JSR   <SER_ANA                   ; Enable the SSI for analog boards
   BSET  #CDAC,X:<LATCH             ; Disable clearing of all DACs
   BCLR  #ENCK,X:<LATCH             ; Disable DAC output switches
   MOVEP X:LATCH,Y:WRLATCH 
; Turn analog power on to controller boards, but not yet to IR array
   BSET  #LVEN,X:PBD                ; LVEN = HVEN = 1 => Power reset
   BSET  #HVEN,X:PBD
; Now ramp up the low voltages (+/- 6.5V, 16.5V) and delay them to turn on
   BCLR  #LVEN,X:PBD                ; LVEN = Low => Turn on +/- 6.5V, 
   MOVE  Y:<PWR_DLY,A               ;   +/- 16.5V
   JSR   <CON_DELAY
; Zero all bias voltages and enable DAC output switches
   MOVE  #<ZERO_BIASES,R0           ; Get starting address of DAC values
   JSR   <SET_DAC
   MOVE  X:<THREE,A
   JSR   <CON_DELAY
   BSET  #ENCK,X:<LATCH             ; Enable clock and DAC output switches
   MOVEP X:LATCH,Y:WRLATCH          ; Disable DAC clearing, enable clocks
; Turn on Vdd = digital power unit cell to the IR array
   MOVEP Y:VDD,X:SSITX              ; pin #5 = Vdd = digital power on array
; Delay for the IR array to settle down
   MOVE  Y:<VDD_DLY,A               ; Delay for the IR array to settle
   JSR   <CON_DELAY

; Set DC bias DACs
SETBIAS
   JSR   <SER_ANA                   ; Enable the SSI for analog boards
   JSR   <PAL_DLY                   ; Wait for port to be enabled
   MOVE  #<DC_BIASES,R0             ; Get starting address of DAC values
   JSR   <SET_DAC
   MOVE  X:<THREE,A                 ; Delay three millisec to settle
   JSR   <CON_DELAY
; Set clock driver DACs
   MOVE  #<DACS,R0                  ; Get starting address of DAC values
   JSR   <SET_DAC
; Turn continuous reset mode on, disable the SSI, and return 
   MOVE  #CONT_RST,X0
   MOVE  X0,X:<IDL_ADR
   JMP   <FINISH 

; Generate a synthetic image by simply incrementing the pixel counts
SYNTHETIC_IMAGE
   CLR   A
   MOVE  A,Y:<TST_DAT
   DO    #1024,LPR_TST              ; Loop over each line readout
   DO    #1024,LSR_TST              ; Loop over number of pixels per line
   REP   #20                        ; #20 => 1.0 microsec per pixel
   NOP

; Increment pixel counts by one
   MOVE  X:<ONE,X1
   MOVE  Y:<TST_DAT,A
   ADD   X1,A                       ; Pixel data = Y:TST_DAT = Y:TST_DAT + 1
   MOVE  A,Y:<TST_DAT
   MOVEP A,Y:WRFO                   ; Transmit to fiber optic  
LSR_TST  
   NOP
LPR_TST
   JMP   <RDA_END                   ; Normal exit

; Alert the PCI interface board that images are coming soon
PCI_READ_IMAGE
   MOVE  #$020104,X0
   JSR   <XMT_FO
   MOVE  #'RDA',X0
   JSR   <XMT_FO
   MOVE  Y:<NCOLS,X0
   JSR   <XMT_FO
   MOVE  Y:<NROWS,A
   LSR   A                          ; /2 for CDS
   MOVE  A1,X0
   JSR   <XMT_FO
   RTS

; Put PCI board in reading image out mode to block commands to the timing board
READING_IMAGE_ON
   MOVE  #$020102,X0
   JSR   <XMT_FO
   MOVE  #'RDI',X0
   JSR   <XMT_FO
   RTS

; Restore PCI board to normally processing comamnds
READING_IMAGE_OFF
   MOVE  #$020102,X0
   JSR   <XMT_FO
   MOVE  #'RDO',X0
   JSR   <XMT_FO
   RTS

; Transmit a word to the PCI board over the fiber optics data link
XMT_FO
   MOVEP X0,Y:WRFO                  ; Write a word to the FO transmitter
   REP   #15                        ; Delay a bit for the fiber optics to transmit
   NOP
   RTS

; Specify subarray readout coordinates, assuming only one box. Maintain
;   compatability with CCD readout of multiple boxes.
SET_SUBARRAY_SIZES
   CLR   A  
   MOVE  X:(R4)+,X0                 ; # of bias pixels to read (not used)
   MOVE  X:(R4)+,X0
   MOVE  X0,Y:<NCOLS                ; Number of columns in subimage read
   MOVE  X:(R4)+,A
   LSL   A                          ; * 2 for CDS correction
   MOVE  A1,Y:<NROWS                ; Number of rows in subimage read   
   JMP   <FINISH

; Call this routine once for every subarray to be added to the table
SET_SUBARRAY_POSITIONS
   MOVE  X:(R4)+,X0                 ; Number of row clears
   MOVE  X0,Y:<ROW_OFFSET
   MOVE  X:(R4)+,X0                 ; Number of column clears
   MOVE  X0,Y:<COL_OFFSET
   MOVE  X:(R4)+,X0                 ; Not used  
   JMP   <FINISH

; Command table - make sure there are exactly 32 entries in it
   IF    @SCP("DOWNLOAD","HOST")    ; Download address
      ORG   X:COM_TBL,X:COM_TBL        
   ELSE                             ; EEPROM address
      ORG   P:COM_TBL,P:APL_NUM*N_W_APL+APL_LEN+MISC_LEN 
   ENDIF

   DC 'SEX',START_EXPOSURE          ; Start exposure
   DC 'AEX',ABR_EXP                 ; End current exposure
   DC 'PON',PWR_ON                  ; Turn on analog power
   DC 'POF',PWR_OFF                 ; Turn off analog power
   DC 'SET',SET_EXT                 ; Set exposure time
   DC 'SBN',SET_BIAS_NUMBER         ; Set bias number
   DC 'SBV',SETBIAS                 ; Set DC bias supply voltages
   DC 'SSS',SET_SUBARRAY_SIZES
   DC 'SSP',SET_SUBARRAY_POSITIONS
   DC 'RCC',READ_CONTROLLER_CONFIGURATION 
   DC 'DON',START                   ; Nothing special
   DC 0,START,0,START,0,START,0,START
   DC 0,START,0,START,0,START,0,START
   DC 0,START,0,START,0,START,0,START
   DC 0,START,0,START,0,START,0,START
   DC 0,START,0,START,0,START,0,START
   DC 0,START

   IF    @SCP("DOWNLOAD","HOST")    ; Download address
      ORG   Y:0,Y:0     
   ELSE                             ; EEPROM address continues from P: above
      ORG   Y:0,P:      
   ENDIF

DUMMY                DC 0
NCOLS                DC 512         ; Number of columns
NROWS                DC 1024        ; Number of rows in two frames (CDS)
N_RA                 DC 1           ; Desired number of reset/read pairs
COL_OFFSET           DC 0           ; Number of columns to skip
ROW_OFFSET           DC 0           ; Number of rows to skiP
NROWS_DIV_2          DC 0           ; Number of columns divided by 2
NCOLS_DIV_2_MINUS_1  DC 0           ; Number of columns divided by 2 minus 1
COL_SKP              DC 0           ; Argument to DO loop for skipping
RST_DLY              DC 1           ; Delay after array reset for settling
PWR_DLY              DC 100         ; Delay in millisec for power to turn on
VDD_DLY              DC 300         ; Delay in millisec for VDD to settle   
N_RSTS               DC 1           ; Number of resets
CONFIG               DC CC          ; Controller configuration
TST_DAT              DC 0           ; Test image data for synthetic images

; Start the voltage and timing tables at a fixed address
   IF    @SCP("DOWNLOAD","HOST")    ; Download address
      ORG   Y:TBL_ADR,Y:TBL_ADR  
   ELSE                             ; EEPROM
      ORG   Y:TBL_ADR,P:APL_NUM*N_W_APL+APL_LEN+MISC_LEN+$4F 
   ENDIF

; Miscellaneous definitions
VIDEO    EQU $000000                ; Video board select = 0 for biases
CLK2     EQU $002000                ; Clock board select = 2 
DELAY    EQU $2C0000                ; Delay for clocking ops (20 ns, 160 if MSB set)
VP_DLY   EQU $1B0000                ; Video delay time for 1 microsec/pixel

  IF @SCP("QUAD","0")
SXMIT    EQU $00F000                ; Series transmit A/D channel #0 only
  ENDIF
  IF @SCP("QUAD","1")
SXMIT    EQU $00F021                ; Series transmit A/D channel #1 only
  ENDIF
  IF @SCP("QUAD","2")
SXMIT    EQU $00F042                ; Series transmit A/D channels #0-#3
  ENDIF
  IF @SCP("QUAD","3")
SXMIT    EQU $00F063                ; Series transmit A/D channels #0-#3
  ENDIF

;  Clock voltage definitions
CLK_HIGH EQU $CC0                   ; ~+4V, assuming +VREF = +2.5
CLK_LOW  EQU $0F4                   ; ~+.30V, assuming -VREF =  0.0

; Table of offset values begins at Y:$10

; DAC settings for the video offsets
DC_BIASES   DC ZERO_BIASES-DC_BIASES-1
OFF_0       DC $0c0000              ; Input offset board #0, channel A
OFF_1       DC $0c4000              ; Input offset board #0, channel B
OFF_2       DC $1c0000              ; Input offset board #1, channel A
OFF_3       DC $1c4000              ; Input offset board #1, channel B

; DAC settings to generate DC bias voltages for the array
VOFFSET     DC $0c8e65              ; pin #1 = preamp offset = +4.2 volts
VRESET      DC $0cc2e1              ; pin #2 = reset = +0.9 volts
VD          DC $0d0fff              ; pin #3 = analog power = +5.0 volts
ICTL        DC $0d4a8c              ; pin #4 = current control = +3.3 volts
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
   DC  READ_ON-DACS-1
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

READ_OFF                            ; Turn READ ON for readout and reset
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
;  DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY

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
   DC $000033                       ; Padding
   DC $140033                       ; Padding
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Padding
   DC $000033                       ; Padding

SHIFT_EVEN_ROW
   DC READ_EVEN_ROW_PIXELS-SHIFT_EVEN_ROW-2
   DC CLK2+H_READ+L_PIXEL+L_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
;   DC CLK2+H_READ+L_PIXEL+H_LSYNC+H_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   
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
   DC SXMIT_TWO_PIXELS-SHIFT_EVEN_ROW_PIXELS-2
   DC CLK2+H_READ+H_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC $000033			    ; Padding
   DC $140033                       ; Padding
   DC CLK2+H_READ+L_PIXEL+H_LSYNC+L_LINE+H_FSYNC+H_RST+DELAY
   DC VP_DLY                        ; A/D sample
   DC $010033                       ; Start A/D conversion
   DC $000033                       ; Padding

SXMIT_TWO_PIXELS
   DC END_TBL-SXMIT_TWO_PIXELS-2
   DC DELAY+$000033
   DC VP_DLY                        ; A/D sample
   DC $000033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit 1 pixel's data
   DC DELAY+$000033
   DC VP_DLY                        ; A/D sample
   DC $000033                       ; Start A/D conversion
   DC SXMIT                         ; Series transmit 1 pixel's data

END_TBL  DC 0                       ; End of waveform tables

; Check for EEPROM overflow in the EEPROM case
   IF    @SCP("DOWNLOAD","EEPROM")
      IF    @CVS(N,@LCV(L))>(APL_NUM+1)*N_W_APL
         WARN  'EEPROM overflow!' 
      ENDIF
   ENDIF

   ENDSEC                           ; End of section 
   END                              ; End of program
