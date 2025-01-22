       COMMENT *
This is a header file that is shared between the fiber optic timing board
boot and application code files
   **

   PAGE  132                        ; Printronix page width - 132 columns

; Some basic structural definitions
APL_ADR     EQU $130                ; P: memory location where application code begins
APL_LEN     EQU $200-APL_ADR        ; Maximum length of application program
MISC_LEN    EQU $280                ; Maximum length of "miscellanous" code
COM_LEN     EQU $40                 ; Length of memory for application commands
TIM_ISR     EQU $3C                 ; DSP timer interrupt service routine address
PGM_CON     EQU $3E                 ; Program continues on here
COM_TBL     EQU $80                 ; Starting address of command table in X: memory
N_W_APL     EQU $500                ; Number of words in each application
NUM_COM     EQU 40                  ; Number of entries in command table

RST_ISR     EQU $00                 ; Hardware reset interrupt
ROM_ID      EQU $06                 ; Location of program Identification = SWI interrupt
START       EQU $08                 ; Starting address of program
RCV_BUF     EQU $60                 ; Starting address of receiver buffer in X:
TBL_ADR     EQU $0F                 ; (IR) Waveform tables starting address

ROM_OFF     EQU $4000               ; Boot program offset address in EEPROM
LD_X        EQU $4200               ; Assembler loads X: starting at this EEPROM address
RD_X        EQU $C600               ; DSP reads X: from this EEPROM address

; Define DSP port addresses
WRSS        EQU $FF80               ; Write clock driver and VP switch states
RDFO        EQU $FFC0               ; Read serial receiver fiber optic contents
WRFO        EQU $FFC0               ; Write to fiber optic serial transmitter 
RDAD        EQU $FFA0               ; Read A/D datum into DSP
RDAD0       EQU $FFA0               ; Address for reading A/D #0
RDAD1       EQU $FFA1               ; Address for reading A/D #1
WRLATCH     EQU $FFC1               ; Write to timing board latch
RSTWDT      EQU $6000               ; Address to reset the timing board watchdog timer
BCR         EQU $FFFE               ; Bus (=Port A) Control Register -> Wait States
PBC         EQU $FFE0               ; Port B Control Register
PBDDR       EQU $FFE2               ; Port B Data Direction Register
PBD         EQU $FFE4               ; Port B Data Register
PCC         EQU $FFE1               ; Port C Control Register
PCDDR       EQU $FFE3               ; PortC Data Direction Register
PCD         EQU $FFE5               ; Port C Data Register
IPR         EQU $FFFF               ; Interrupt Priority Register
SSITX       EQU $FFEF               ; SSI Transmit and Receive data register
SSIRX       EQU $FFEF               ; SSI Transmit and Receive data register
SSISR       EQU $FFEE               ; SSI Status Register
CRA         EQU $FFEC               ; SSI Control Register A
CRB         EQU $FFED               ; SSI Control Regsiter B
TCSR        EQU $FFDE               ; Timer control and status register
TCR         EQU $FFDF               ; Timer count register

; Hardware bit definitions all over the place
SSI_TDE     EQU 6                   ; SSI Transmitter data register empty
SSI_RDF     EQU 7                   ; SSI Receiver data register full
LVEN        EQU 2                   ; Low voltage enable (+/-15 volt nominal)
HVEN        EQU 3                   ; Enable high voltage (+32V nominal)
TIM_U_RST   EQU 5                   ; Timing to utility board reset bit number in U25
PWRST       EQU 13                  ; Power control board reset
RST_FIFO    EQU 7                   ; Reset FIFO bit number in control latch U25
EF          EQU 9                   ; FIFO empty flag, low true
TIM_BIT     EQU 0                   ; Timer status bit
WW          EQU 1                   ; Word width = 1 for 16-bit image data, 0 for 24-bit
CDAC        EQU 0                   ; Bit number in U25 for clearing DACs
ENCK        EQU 2                   ; Bit number in U25 for enabling analog switches
DUALCLK     EQU 1                   ; Set to clock two halves of clock driver board together

; Software status bits, defined at X:<STATUS = X:0
ST_RCV      EQU 0                   ; Set if FO, cleared if SSI
TST_IMG     EQU 10                  ; Set if controller is to generate a test image
SHUT        EQU 11                  ; Set if opening shutter at beginning of exposure

; Software status bits, defined at X:<STATUS = X:0
IDLMODE     EQU 2                   ; Set if need to idle after readout
ST_SHUT     EQU 3                   ; Set to indicate shutter is closed, clear for open
ST_RDC      EQU 4                   ; Set if executing 'RDC' command - reading out
SPLIT_S     EQU 5                   ; Set if split serial
SPLIT_P     EQU 6                   ; Set if split parallel
MPP         EQU 7                   ; Set if parallels are in MPP mode

; Specify controller configuration bits of the X:STATUS word
;   to describe the software capabilities of this application file
; The bit is set (=1) if the capability is supported by the controller

      COMMENT *
BIT #'s     FUNCTION
2,1,0    Video Processor
 000        CCD Rev. 3
 001        CCD Gen I
 010        IR Rev. 4
 011        IR Coadder

4,3      Timing Board
 00         Rev. 4, Gen II
 01         Gen I

6,5      Utility Board
 00         No utility board
 01         Utility Rev. 3

7        Shutter
 0          No shutter support
 1          Yes shutter support

9,8      Temperature readout
 00         No temperature readout
 01         Polynomial Diode calibration
 10         Linear temperature sensor calibration

10       Subarray readout
 0          Not supported
 1          Yes supported

11       Binning
 0          Not supported
 1          Yes supported

12       Split-Serial readout
 0          Not supported
 1          Yes supported

13       Split-Parallel readout
 0          Not supported
 1          Yes supported

14       MPP = Inverted parallel clocks
 0          Not supported
 1          Yes supported

16,15    Clock Driver Board
 00         Rev. 3
 11         No clock driver board (Gen I)

19,18,17 Special implementations
 000        Somewhere else
 001        Mount Laguna Observatory
 010        NGST Aladdin
 xxx        Other

   **

CCDVIDREV3B    EQU $000000          ; CCD Video Processor Rev. 3
VIDGENI        EQU $000001          ; CCD Video Processor Gen I
IRREV4         EQU $000002          ; IR Video Processor Rev. 4
COADDER        EQU $000003          ; IR Coadder
TIMREV4        EQU $000000          ; Timing Rev. 4
TIMGENI        EQU $000008          ; Timing Gen I
UTILREV3       EQU $000020          ; Utility Rev. 3 supported
SHUTTER_CC     EQU $000080          ; Shutter supported
TEMP_POLY      EQU $000100          ; Polynomial calibration
TEMP_LINEAR    EQU $000200          ; Linear calibration
SUBARRAY       EQU $000400          ; Subarray readout supported
BINNING        EQU $000800          ; Binning supported
SPLIT_SERIAL   EQU $001000          ; Split serial supported
SPLIT_PARALLEL EQU $002000          ; Split parallel supported
MPP_CC         EQU $004000          ; Inverted clocks supported
CLKDRVGENI     EQU $018000          ; No clock driver board - Gen I
MLO            EQU $020000          ; Set if Mount Laguna Observatory
NGST           EQU $040000          ; NGST Aladdin implementation
