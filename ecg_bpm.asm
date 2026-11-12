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
    ; Cambio a _FOSC_XT para habilitar el cristal externo de 4MHz
    __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _BOREN_OFF & _LVP_OFF & _CPD_OFF & _CP_OFF
    __CONFIG _CONFIG2, _IESO_OFF & _FCMEN_OFF
;===============================================================================
; CONSTANTES
;===============================================================================
UMBRAL_TEMP EQU .40         ; Valor de referencia para 40°C (alarma técnica)
MAX_LPM     EQU .100        ; Límite para activar la alarma de taquicardia
    
    
    
;===============================================================================
; VARIABLES
;===============================================================================
    CBLOCK  0x20
        ; Registros para el conteo de tiempo (Timer 1)
        TIEMPO_L            
        TIEMPO_H            
        
        ; Registros para el cálculo de latidos (División Shift & Subtract)
        DIVIDENDO_L         
        DIVIDENDO_H
        DIVIDENDO_U
        LPM_ACTUAL          ; Resultado final de latidos por minuto
        RESTO_L             
        RESTO_H             
        CONTADOR            
        
        ; --- NUEVAS VARIABLES PARA DISPLAYS ---
        CENTENAS            ; Guarda el dígito de las centenas (0-9)
        DECENAS             ; Guarda el dígito de las decenas (0-9)
        UNIDADES            ; Guarda el dígito de las unidades (0-9)
        TEMP_LPM            ; Variable temporal para no borrar el LPM original
        ESTADO_MUX          ; Lleva la cuenta de qué display encender (0, 1 o 2)
        
        ; Variables para el multiplexado de los 3 displays de 7 segmentos
        DIGITO_U            
        DIGITO_D            
        DIGITO_C            
        
        ; Banderas del sistema
        FLAGS               ; Bit0=Alarma_Temp, Bit1=Alarma_LPM, Bit2=Freeze
    ENDC
;===============================================================================
; MACROS
;===============================================================================

; Declaracion de macros (si son necesarias)

;===============================================================================
; VECTORES DE RESET E INTERRUPCION
;===============================================================================
        ORG     0x00                ; Vector de Reset
        GOTO    INICIO

        ORG     0x04                ; Vector de Interrupción
        GOTO    RUTINA_ISR          ; Salta a la rutina que está más abajo

        ORG     0x05                ; Inicio del programa principal
	
	
;===============================================================================
; PROGRAMA PRINCIPAL (CONFIGURACIÓN INICIAL)
;===============================================================================
INICIO:
        ; 1. Configuración Analógica/Digital (Registros ANSEL)
        BANKSEL ANSEL
        MOVLW   b'00000011'         ; AN0 (Temp LM35) y AN1 (ECG) como analógicos
        MOVWF   ANSEL
        CLRF    ANSELH              ; El resto de los pines como I/O digitales

        ; 2. Configuración de Puertos (0=Salida, 1=Entrada)
        BANKSEL TRISA
        MOVLW   b'00000011'         ; RA0 y RA1 entradas analógicas
        MOVWF   TRISA

        BANKSEL TRISB
        MOVLW   b'00000001'         ; RB0 entrada (Pulso del comparador), RB1-RB7 salidas (Segmentos)
        MOVWF   TRISB

        BANKSEL TRISC
        MOVLW   b'10100000'         ; RC7 entrada (RX USART), RC6 salida (TX USART), RC0 salida (Buzzer)
        MOVWF   TRISC

        BANKSEL TRISD
        CLRF    TRISD               ; Todo el Puerto D como salida (Control de transistores/dígitos)

        BANKSEL TRISE
        MOVLW   b'00000011'         ; RE0 y RE1 como entradas (Pulsadores Freeze y Mute)
        MOVWF   TRISE

        ; 3. Limpieza de Puertos (Arrancar todo apagado)
        BANKSEL PORTA
        CLRF    PORTA
        CLRF    PORTB
        CLRF    PORTC
        CLRF    PORTD
        CLRF    PORTE
        
        ; 4. Configuración de la Interrupción Externa (RB0/INT)
        BANKSEL OPTION_REG
        BSF     OPTION_REG, 6       ; Configurar INTEDG: Interrupción en flanco de subida (detecta el pulso del LM311)
        
        BANKSEL INTCON
        BSF     INTCON, 4           ; Habilitar INTE (Interrupción externa en RB0)
        ; (No habilitamos GIE todavía, lo haremos justo antes del MAIN_LOOP)
	
	
; 5. Configuración del ADC (Conversor Analógico a Digital)
        BANKSEL ADCON1
        MOVLW   b'10000000'         ; ADFM=1 (Justificación a la derecha para 10 bits), Vref = VDD/VSS
        MOVWF   ADCON1
        BANKSEL ADCON0
        MOVLW   b'01000001'         ; Fosc/8, Canal AN0 (Sensor LM35), ADON=1 (Módulo encendido)
        MOVWF   ADCON0

        ; 6. Configuración del Timer 0 (Multiplexado de Displays)
        BANKSEL OPTION_REG
        ; Precaución: Configurar INTEDG (bit 6) en 1 para RB0, y los bits del Timer 0 (PS=011) en el mismo viaje.
        MOVLW   b'01000011'         ; INTEDG=1 (flanco subida), T0CS=0 (Fosc/4), PSA=0, PS2:PS0=011 (Prescaler 1:16)
        MOVWF   OPTION_REG

        ; 7. Configuración del Timer 1 (Medición de tiempo entre latidos)
        BANKSEL T1CON
        MOVLW   b'00110000'         ; T1CKPS=11 (Prescaler 1:8), Oscilador apagado, TMR1CS=0 (Fosc/4), TMR1ON=0
        MOVWF   T1CON

        ; 8. Habilitación de Interrupciones
        BANKSEL PIE1
        BSF     PIE1, 0             ; TMR1IE: Habilita interrupción por desborde del Timer 1
        
        BANKSEL INTCON
        BSF     INTCON, 5           ; T0IE: Habilita interrupción del Timer 0 (para refrescar displays)
        BSF     INTCON, 6           ; PEIE: Habilita interrupciones periféricas (necesario para Timer 1 y ADC)
        BSF     INTCON, 7           ; GIE: Habilitación global de interrupciones (Activa todo el sistema)

	;MIRAR DE HACER EN 10
	
; 9. Configuración del USART (Comunicación Serie a PC)
        BANKSEL SPBRG
        MOVLW   .25                 ; Velocidad de 9600 bps (para Fosc = 4 MHz)
        MOVWF   SPBRG
        BANKSEL TXSTA
        MOVLW   b'00100100'         ; TXEN=1 (Transmite), BRGH=1 (Alta vel.), SYNC=0 (Asíncrono)
        MOVWF   TXSTA
        BANKSEL RCSTA
        MOVLW   b'10000000'         ; SPEN=1 (Habilita el puerto serie en pines RC6/RC7)
        MOVWF   RCSTA	
	
;===============================================================================
; VECTOR DE INTERRUPCION (ISR)
;===============================================================================

;===============================================================================
; PROGRAMA PRINCIPAL
;===============================================================================
        ORG     0x50                ; Espacio seguro después de los vectores
MAIN_LOOP:
    
    ; --- A. Lectura de Botones de Usuario ---
    ; Botón Freeze en RE0 (Congela displays)
    BTFSS   PORTE, 0            ; ¿Pulsaron RE0? (pull-up o pull-down según diseño, asumimos activo en alto)
    GOTO    BOTON_FREEZE_LIBRE
    ; Acción si se presiona Freeze: ponemos bandera
    BSF     FLAGS, 2            ; Activa bit de Freeze
    GOTO    CHECK_MUTE
BOTON_FREEZE_LIBRE:
    BCF     FLAGS, 2            ; Libera bit de Freeze

CHECK_MUTE:
    ; Botón Mute en RE1 (Silencia alarma de taquicardia o térmica)
    BTFSS   PORTE, 1            ; ¿Pulsaron RE1?
    GOTO    BOTON_MUTE_LIBRE
    BCF     PORTC, 0            ; Apaga inmediatamente el buzzer en RC0 (Mute)
    GOTO    LEER_SENSOR_TEMP
BOTON_MUTE_LIBRE:

    ; --- B. Monitoreo de Temperatura (Sensor LM35 en AN0) ---
LEER_SENSOR_TEMP:
    BANKSEL ADCON0
    BSF     ADCON0, 2           ; Selecciona canal AN0 (CHS0=0, CHS1=0, CHS2=0, CHS3=0) -> Canal 0
    BSF     ADCON0, 1           ; GO/DONE = 1 (Inicia conversión AD)
    
ESPERAR_ADC:
    BTFSC   ADCON0, 1           ; ¿Terminó la conversión?
    GOTO    ESPERAR_ADC         ; Si sigue en 1, espera
    
    ; Comparamos el resultado del ADC (ADRESH) con nuestra constante de temperatura (40°C)
    BANKSEL ADRESH
    MOVF    ADRESH, W
    SUBLW   UMBRAL_TEMP         ; Resta: UMBRAL_TEMP - ADRESH
    BTFSS   STATUS, C           ; ¿El resultado dio negativo? (Significa que ADRESH > 40°C)
    GOTO    ACTIVAR_ALARMA_TEMP
    GOTO    APAGAR_ALARMA_TEMP

ACTIVAR_ALARMA_TEMP:
    BSF     PORTC, 0            ; Enciende el Buzzer (RC0) y LED de alerta técnica
    BSF     FLAGS, 0            ; Setea bandera de alarma térmica
    GOTO    CONTINUAR_PRINCIPAL

APAGAR_ALARMA_TEMP:
    BCF     FLAGS, 0            ; Limpia bandera

CONTINUAR_PRINCIPAL:
        ; --- C. Transmisión USART de la señal cruda del ECG hacia la PC ---
        BANKSEL ADCON0
        ; Cambiamos del canal AN0 (Temp) al canal AN1 (ECG)
        BCF     ADCON0, 2           ; CHS0 = 0
        BSF     ADCON0, 3           ; CHS1 = 1  (Canal 01 = AN1)
        BSF     ADCON0, 1           ; GO/DONE = 1 (Inicia conversión de la onda)

ESPERAR_ADC_ECG:
        BTFSC   ADCON0, 1           ; ¿Terminó de digitalizar?
        GOTO    ESPERAR_ADC_ECG
        
        ; Tomamos el dato digitalizado y lo enviamos por el puerto serie
        BANKSEL ADRESH
        MOVF    ADRESH, W           ; Cargamos los 8 bits más altos de la conversión
        BANKSEL TXREG
        MOVWF   TXREG               ; Lo disparamos hacia la computadora (GUI)

ESPERAR_TX:
        BANKSEL TXSTA
        BTFSS   TXSTA, 1            ; TRMT: ¿Se vació el buffer de transmisión?
        GOTO    ESPERAR_TX          ; Espera hasta que el dato salga por completo hacia la PC
        
        GOTO    MAIN_LOOP           ; Vuelve arriba de todo a revisar botones, temp y repetir
    
    GOTO    MAIN_LOOP           ; Bucle infinito principal
	
;===============================================================================
; SUBRUTINAS PRINCIPALES
;===============================================================================

;-------------------------------------------------------------------------------
; @brief PROCESAR_LATIDO
; @details Se llama desde la interrupción RB0. Calcula el tiempo transcurrido 
;          desde el latido anterior (leyendo el Timer 1) y ejecuta la división
;          por Shift & Subtract para obtener los LPM.
;-------------------------------------------------------------------------------
PROCESAR_LATIDO:
        ; 1. Detenemos el Timer 1 un instante para leerlo sin que cambie de valor
        BANKSEL T1CON
        BCF     T1CON, 0            ; TMR1ON = 0
        
        ; 2. Copiamos el valor del Timer 1 (Tiempo entre latidos) a nuestras variables
        BANKSEL TMR1L
        MOVF    TMR1L, W
        MOVWF   TIEMPO_L
        MOVF    TMR1H, W
        MOVWF   TIEMPO_H
        
        ; 3. Reiniciamos el Timer 1 a 0 para empezar a contar hasta el próximo latido
        CLRF    TMR1H
        CLRF    TMR1L
        BANKSEL T1CON
        BSF     T1CON, 0            ; TMR1ON = 1 (Vuelve a arrancar)
        
       ; 4. Rutina de División (Shift & Subtract) para calcular LPM
        ; Dividimos la constante 7.500.000 (0x007270E0) por el TIEMPO medido.
        MOVLW   0xE0                ; Cargamos la constante 24-bits
        MOVWF   DIVIDENDO_L
        MOVLW   0x70
        MOVWF   DIVIDENDO_H
        MOVLW   0x72
        MOVWF   DIVIDENDO_U
        
        CLRF    RESTO_L             ; Limpiamos los restos
        CLRF    RESTO_H
        MOVLW   .24                 ; Son 24 desplazamientos (24 bits)
        MOVWF   CONTADOR

DIV_LOOP:
        ; Desplazamos Dividendo a la izquierda
        BCF     STATUS, C
        RLF     DIVIDENDO_L, F
        RLF     DIVIDENDO_H, F
        RLF     DIVIDENDO_U, F
        ; Desplazamos Resto a la izquierda llevándonos el bit de acarreo
        RLF     RESTO_L, F
        RLF     RESTO_H, F

        ; Restamos TIEMPO del RESTO (Resto = Resto - Tiempo)
        MOVF    TIEMPO_L, W
        SUBWF   RESTO_L, F
        BTFSS   STATUS, C           ; ¿Hubo préstamo (borrow)?
        DECF    RESTO_H, F          ; Si hubo, descontamos del byte alto
        MOVF    TIEMPO_H, W
        SUBWF   RESTO_H, F

        ; Verificamos si la resta fue exitosa (Resto >= 0)
        BTFSS   STATUS, C
        GOTO    DIV_RESTAURA        ; Si dio negativo, deshacemos la resta
        
        BSF     DIVIDENDO_L, 0      ; Si dio positivo, el bit del cociente es 1
        GOTO    DIV_SIGUIENTE

DIV_RESTAURA:
        ; Sumamos el TIEMPO de vuelta para deshacer la resta inválida
        MOVF    TIEMPO_L, W
        ADDWF   RESTO_L, F
        BTFSC   STATUS, C
        INCF    RESTO_H, F
        MOVF    TIEMPO_H, W
        ADDWF   RESTO_H, F

DIV_SIGUIENTE:
        DECFSZ  CONTADOR, F         ; ¿Ya hicimos los 24 bits?
        GOTO    DIV_LOOP            ; Si no, repetimos
        
        ; Al terminar, el resultado queda guardado en la parte baja del dividendo
        MOVF    DIVIDENDO_L, W
        MOVWF   LPM_ACTUAL
	
        ; 5. Verificamos Alarma de Taquicardia
        MOVF    LPM_ACTUAL, W
        SUBLW   MAX_LPM             ; Resta: 100 - LPM_ACTUAL
        BTFSS   STATUS, C           ; Si el resultado es negativo, hay taquicardia (>100)
        GOTO    ACTIVAR_ALARMA_LPM
        GOTO    APAGAR_ALARMA_LPM

ACTIVAR_ALARMA_LPM:
        ; Si no está en MUTE, enciende el buzzer
        BTFSS   PORTE, 1            ; ¿El botón Mute está presionado?
        BSF     PORTC, 0            ; Enciende Buzzer (RC0)
        BSF     FLAGS, 1            ; Setea bandera de taquicardia
        GOTO    ACTUALIZAR_DISPLAYS

APAGAR_ALARMA_LPM:
        BCF     FLAGS, 1            ; Limpia bandera de taquicardia
        ; Solo apagamos el buzzer si tampoco hay alarma de temperatura (bit 0 de FLAGS)
        BTFSS   FLAGS, 0
        BCF     PORTC, 0            ; Apaga Buzzer
ACTUALIZAR_DISPLAYS:
        ; 1. Extraemos los dígitos llamando a la rutina de conversión
        CALL    BIN2BCD
        
        ; 2. Convertimos el número de Unidades a código de 7 segmentos
        MOVF    UNIDADES, W
        CALL    TABLA_7SEG
        MOVWF   DIGITO_U
        
        ; 3. Convertimos las Decenas a código de 7 segmentos
        MOVF    DECENAS, W
        CALL    TABLA_7SEG
        MOVWF   DIGITO_D
        
        ; 4. Convertimos las Centenas a código de 7 segmentos
        MOVF    CENTENAS, W
        CALL    TABLA_7SEG
        MOVWF   DIGITO_C
        
        RETURN

;-------------------------------------------------------------------------------
; @brief MULTIPLEXAR_DISPLAYS
; @details Apaga y enciende rotativamente un transistor a la vez (RD0, RD1, RD2)
;-------------------------------------------------------------------------------
MULTIPLEXAR_DISPLAYS:
        BTFSC   FLAGS, 2            ; ¿Está presionado Freeze?
        RETURN                      ; Si es sí, sale sin actualizar
        
        BANKSEL PORTD
        CLRF    PORTD               ; Apagamos los 3 displays para evitar luz fantasma
        
        MOVF    ESTADO_MUX, W
        BTFSC   STATUS, Z           ; Si ESTADO_MUX es 0, salta a centenas
        GOTO    MUX_CENTENAS
        SUBLW   .1                  
        BTFSC   STATUS, Z           ; Si era 1 (1-1=0), salta a decenas
        GOTO    MUX_DECENAS
        GOTO    MUX_UNIDADES        ; Si es 2, salta a unidades

MUX_CENTENAS:
        BANKSEL PORTB
        MOVF    DIGITO_C, W
        MOVWF   PORTB               ; Envia el dibujo de la centena a los segmentos
        BANKSEL PORTD
        BSF     PORTD, 2            ; Enciende el transistor de la Centena (RD2)
        INCF    ESTADO_MUX, F       ; Pasa al estado 1 para la próxima vuelta
        RETURN
        
MUX_DECENAS:
        BANKSEL PORTB
        MOVF    DIGITO_D, W
        MOVWF   PORTB
        BANKSEL PORTD
        BSF     PORTD, 1            ; Enciende el transistor de la Decena (RD1)
        INCF    ESTADO_MUX, F       ; Pasa al estado 2
        RETURN
        
MUX_UNIDADES:
        BANKSEL PORTB
        MOVF    DIGITO_U, W
        MOVWF   PORTB
        BANKSEL PORTD
        BSF     PORTD, 0            ; Enciende el transistor de la Unidad (RD0)
        CLRF    ESTADO_MUX          ; Vuelve al estado 0 para reiniciar el ciclo
        RETURN

	
;-------------------------------------------------------------------------------
; @brief BIN2BCD
; @details Convierte el valor hexadecimal de LPM_ACTUAL en dígitos decimales.
;-------------------------------------------------------------------------------
BIN2BCD:
        MOVF    LPM_ACTUAL, W
        MOVWF   TEMP_LPM            ; Hacemos copia de seguridad
        CLRF    CENTENAS
        CLRF    DECENAS
        CLRF    UNIDADES
        
BCD_100:
        MOVLW   .100
        SUBWF   TEMP_LPM, W
        BTFSS   STATUS, C           ; ¿El resultado fue negativo?
        GOTO    BCD_10              ; Si es negativo, pasamos a restar de a 10
        MOVWF   TEMP_LPM            ; Guardamos la resta
        INCF    CENTENAS, F         ; Sumamos 1 a las centenas
        GOTO    BCD_100
        
BCD_10:
        MOVLW   .10
        SUBWF   TEMP_LPM, W
        BTFSS   STATUS, C
        GOTO    BCD_1
        MOVWF   TEMP_LPM
        INCF    DECENAS, F
        GOTO    BCD_10
        
BCD_1:
        MOVF    TEMP_LPM, W
        MOVWF   UNIDADES            ; El resto directo a las unidades
        RETURN

;-------------------------------------------------------------------------------
; @brief TABLA_7SEG
; @details Devuelve el código para cátodo común. Desplazado 1 bit a la izquierda 
;          porque RB0 está ocupado por la interrupción.
;-------------------------------------------------------------------------------
TABLA_7SEG:
        ADDWF   PCL, F              ; Salto indexado sumando W al Program Counter
        RETLW   0x7E                ; Número 0
        RETLW   0x0C                ; Número 1
        RETLW   0xB6                ; Número 2
        RETLW   0x9E                ; Número 3
        RETLW   0xCC                ; Número 4
        RETLW   0xDA                ; Número 5
        RETLW   0xFA                ; Número 6
        RETLW   0x0E                ; Número 7
        RETLW   0xFE                ; Número 8
        RETLW   0xDE                ; Número 9
    
 ;===============================================================================
; VECTOR DE INTERRUPCION (ISR)
;===============================================================================
        RUTINA_ISR:
        
        ; --- 1. Interrupción del Timer 0 (Multiplexado de Displays) ---
        BTFSS   INTCON, 2           ; ¿Se desbordó el Timer 0 (T0IF)?
        GOTO    CHECK_RB0           ; Si no fue el Timer 0, salta a revisar RB0
        BCF     INTCON, 2           ; Limpia la bandera T0IF
        
        CALL    MULTIPLEXAR_DISPLAYS ; Llama a la rutina que refresca la pantalla
        
        GOTO    FIN_ISR

CHECK_RB0:
        ; --- 2. Interrupción Externa RB0 (Llegó un latido del comparador LM311) ---
        BTFSS   INTCON, 1           ; ¿Hubo flanco en RB0/INT (INTF)?
        GOTO    FIN_ISR             ; Si no, sale
        BCF     INTCON, 1           ; Limpia la bandera INTF
        
        CALL    PROCESAR_LATIDO     ; Llama a la rutina que calcula los LPM
        
FIN_ISR:
        RETFIE                      ; Retorna de la interrupción y reactiva GIE   
    
    
;===============================================================================
; FIN DEL PROGRAMA
;===============================================================================

        END












