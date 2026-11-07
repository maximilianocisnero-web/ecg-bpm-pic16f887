;===============================================================================
; @file        ecg-bpm-pic16f887.asm
; @author      Grupo 17
; @date        07/11/2026
; @version     1.0
; @brief       Sistema de adquisición de ECG y medición de ritmo cardíaco.
;              Muestreo por Timer1 a 500 Hz, detección simple de QRS,
;              cálculo de BPM en ventana de 6 s, display multiplexado,
;              botones de congelamiento y silencio, alarma de taquicardia.
;===============================================================================

        LIST    P=16F887
        #include "p16f887.inc"

;===============================================================================
; CONFIGURACION
;===============================================================================
    __CONFIG _CONFIG1, _FOSC_INTRC_NOCLKOUT & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _CP_OFF
    __CONFIG _CONFIG2, _IESO_OFF & _FCMEN_OFF

;===============================================================================
; CONSTANTES
;===============================================================================

; ---oscilador---
;---Timer1---
;---ADC---
;---deteccion de QRS---
;---ventana de calculo---	
;---Alarma---
;---Display---
;---comunicacion UART---
;===============================================================================
; VARIABLES
;===============================================================================

        CBLOCK  0x20
            ; Declaracion de variables
        ENDC

;===============================================================================
; MACROS
;===============================================================================

; Declaracion de macros (si son necesarias)

;===============================================================================
; VECTOR DE RESET
;===============================================================================

        ORG     0x00
        GOTO    INICIO

;===============================================================================
; PROGRAMA PRINCIPAL
;===============================================================================

        ORG     0x05

INICIO:
        ;---Inicializar el micro---
	
	
	;---configuracion de puertos---
	 BANKSEL TRISA
        BSF     TRISA,0             ; RA0 entrada (AN0)
        
	BANKSEL TRISB
        CLRF    TRISB               ; PORTB salida (segmentos)
        
	BANKSEL TRISD
        CLRF    TRISD               ; PORTD salida (dígitos)
        
	BANKSEL TRISC
        BCF     TRISC,0             ; RC0 salida (buzzer)
        
	BANKSEL TRISE
        BSF     TRISE,0             ; RE0 entrada (freeze)
        BSF     TRISE,1             ; RE1 entrada (mute)

        BANKSEL PORTA
        CLRF    PORTA
        
	BANKSEL PORTB
        CLRF    PORTB
        
	BANKSEL PORTC
        CLRF    PORTC
        
	BANKSEL PORTD
        CLRF     PORTD
	
	;---configuracon del ADC---
	
	
	;---inicializacion de variables---
	
	
	;---configuracion Timer1---
	

MAIN_LOOP:
    
    GOTO    MAIN_BOTONES
	
	
MAIN_BOTONES:
    
    GOTO MAIN_LOOP

;===============================================================================
; SUBRUTINAS
;===============================================================================

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN

;-------------------------------------------------------------------------------
; @brief 
; @details 
;-------------------------------------------------------------------------------

SUBROUTINE:

        ; Instrucciones

        RETURN


;===============================================================================
; FIN DEL PROGRAMA
;===============================================================================

        END


