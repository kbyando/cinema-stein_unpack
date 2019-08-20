;+
; STEIN_ACTIONS
; 
; AUTHOR:
;	Karl Yando
; 
; PURPOSE:
;   "Convenience code", to assist with common tasks:
;
;   (function) GET_SUBSET: searches data array for records with  
;       "EV_CODE", "ADD", and "DET_ID" that match specified values, 
;       and returns a Boolean array, whose indices are easily extracted
;       with IDL's "WHERE" function.
;
;   (function) HISTOGRAM_DATA: wrapper for IDL's "HISTOGRAM" function.
;
;   (procedure) PLOT_HISTOGRAM: convenience procedure that allows user to 
;       specify desired values of EV_CODE, ADD, and DET_ID, and easily
;       generate a histogram plot via IDL's "OPLOT" procedure (NOTE: 
;       requires an existing plot window).
;
;   (function) LOG_UNPACK: mapping of raw telemetered EV_CODE=0 "data" 
;       values (actually log-binned) to keV energy space.
;
; USAGE:
;   < to be written >	
;
; Copyright 2013 Karl Yando
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
; http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.
;-


FUNCTION GET_LENGTH, data
    ; extract array length for 2-D array
    array_info = SIZE(data)
    IF (array_info[0] NE 2) THEN BEGIN
        Print, "ERROR (GET_LENGTH): DATA array of dimension " + String(array_info[0])
        RETURN, -1
    ENDIF ELSE array_len = array_info[2]
    RETURN, array_len
END

FUNCTION GET_SUBSET, data, evcode, add, det_id
; (negative values for "evcode / add / det_id" cause us to skip that filter) 
; requires arguments EVCODE, ADD, DET_ID to be of type SCALAR INTEGER
; returns BOOLEAN ARRAY 
    
    array_len = GET_LENGTH(data)

    ; filter for..
    IF (evcode GE 0) THEN BEGIN                 ; EV CODE
        ev_match = (data[1,*] EQ evcode[0])
    ENDIF ELSE ev_match = REPLICATE(1, array_len)
    IF (add GE 0) THEN BEGIN
        add_match = (data[2,*] EQ add[0])          ; ADD
    ENDIF ELSE add_match = REPLICATE(1, array_len)
    IF (det_id GE 0) THEN BEGIN
        detid_match = (data[3,*] EQ det_id[0])     ; DET_ID
    ENDIF ELSE detid_match = REPLICATE(1, array_len)

    ; combine filters & RETURN (extract indices with WHERE)
    RETURN, (ev_match * add_match * detid_match)
END


FUNCTION HISTOGRAM_DATA, data, INDICES=data_index, FULLSIZE=full_histsize
    ;(HISTOGRAM_DATA): requires argv[0] DATA

    ; process and safe INDEX keyword
    IF ~KEYWORD_SET(data_index) THEN data_index = 0 ELSE $
        IF (data_index[0] LT 0) THEN BEGIN      ; generate a full index 
            array_len = GET_LENGTH(data)
            IF (array_len LE 0) THEN RETURN, -1 $ ; (error)
                ELSE data_index = LIndGEN(GET_LENGTH(data))
        ENDIF
    IF ~KEYWORD_SET(full_histsize) THEN full_histsize = 2L^16 ELSE $
        IF (full_histsize[0] LE 0) THEN full_histsize = 2L^16
        ; (i.e., default to a histogram large enough to cover ADC values)

    ; histogram
    partial = HISTOGRAM(data[5, data_index], BINSIZE=1, OMIN=offset)
    occupied_range = LIndGen(N_ELEMENTS(partial)) + offset
    fullHistogram = ULonArr(full_histsize)
    fullHistogram[occupied_range] = fullHistogram[occupied_range] + partial

    RETURN, fullHistogram
END

PRO PLOT_HISTOGRAM, data, EVCODE=ev_code, ADD=add, DET_IDINDEX=det_id_index, TALLYFLAG = tally_flag, PSYMINDEX = psym_index, COLORINDEX = color_index, FULLSIZE=full_histsize, _REF_EXTRA = pass_thru
   ; WORKZONE 
    ; process and safe EVCODE, ADD, and DET_ID[INDEX] keywords
    ; (note that these values are often scalar [0]; to preserve their 
    ; validity, we require empty arguments to be of the form [-1] instead)
    IF ~(KEYWORD_SET(ev_code)) THEN ev_code = 0
    IF ~(KEYWORD_SET(add)) THEN add = 0
    IF ~(KEYWORD_SET(det_id_index)) THEN det_id_index = 0
   
    IF ~(KEYWORD_SET(tally_flag)) THEN tally_flag = 0
    IF ~(KEYWORD_SET(psym_index)) THEN psym_index = 3
    IF ~(KEYWORD_SET(color_index)) THEN color_index = -1

    IF ~(KEYWORD_SET(full_histsize)) THEN full_histsize = 2L^16 ELSE $
        IF (full_histsize[0] LE 0) THEN full_histsize = 2L^16

    fullRange = LIndGEN(full_histsize) 
    cumuHistogram = LonARR(full_histsize)
    n_psym = N_ELEMENTS(psym_index)
    n_color = N_ELEMENTS(color_index)

    FOR i=0, N_ELEMENTS(det_id_index)-1 DO BEGIN
        data_index = WHERE( GET_SUBSET(data, ev_code[0], add[0], det_id_index[i]) )
        IF (data_index[0] NE -1) THEN BEGIN
            current_channel = HISTOGRAM_DATA(data, INDICES=data_index, FULLSIZE=full_histsize)
            IF (tally_flag) THEN BEGIN
                cumuHistogram = TEMPORARY(cumuHistogram) + current_channel 
            ENDIF ELSE BEGIN
                OPLOT, fullRange, current_channel, PSYM=psym_index[i MOD n_psym],$
                    COLOR=color_index[i MOD n_color], _EXTRA = pass_thru
            ENDELSE
        ENDIF    
    ENDFOR
    IF (tally_flag) THEN BEGIN
            OPLOT, fullRange, cumuHistogram, PSYM=psym_index[i MOD n_psym],$
                COLOR=color_index[i MOD n_color], _EXTRA = pass_thru
    ENDIF
END

FUNCTION LOG_UNPACK, log_steindata
    ; for EVCODE0 events, FSW reduces the quantity of STEIN data
    ;  by pseudo log-binning the 16-bits of ADC resolution into
    ;  7-bits of energy-resolution according to the following scheme:
    ; 
    ;  STEP 1: drop 8 LSBs 
    ;  STEP 2: LOG-BIN to reduce from 8-bits of resolution to 7-bits 
    ; [7-bit data value] = (UPPER 6 BITS)(LSB)
    ;  if LSB = 0, then (UPPER 6 BITS) span 0-64keV with 1keV bins
    ;  if LSB = 1, then (UPPER 6 BITS) span 64-190keV with 2keV bins
    ;           *and* 190keV+ with an integral bin
    ;
    lsb = (log_steindata AND 1L)
    upper6 = ISHFT(log_steindata, -1)
    ; Note: LSB and UPPER6 operations are vector-safe
    
    ; TEST IMPLEMENTATION (unvectorized)
    IF (0) THEN BEGIN 
        ; calculate lower bound on the energy bin (SCALAR)
        IF (lsb) THEN BEGIN                 ; LSB=1, we span 64 - 192(+) keV
            energy_bin = upper6*2 + 64      ; (e.g., upper6=2, so energy_bin=[68,70]keV)
        ENDIF ELSE BEGIN                    ; LSB=0, we span 0 - 64 keV
            energy_bin = upper6             ; (e.g., upper6=2, so energy_bin=[2,3]keV)
        ENDELSE

        ; test to see whether we've done this properly..
        IF (energy_bin LT 64) THEN BEGIN
            orig = ISHFT((energy_bin AND 63b), 1);
        ENDIF ELSE IF (energy_bin LT 128) THEN BEGIN
            orig = ((energy_bin AND 62b) OR 1b);
        ENDIF ELSE IF (energy_bin LT 192) THEN BEGIN
            orig = ((energy_bin AND 62b) OR 65b);
        ENDIF ELSE orig = 127b;
        print, log_steindata, energy_bin, orig
    ENDIF

    ; VECTORIZED (bare minimum)
    ; copy over all of "upper6", which takes care of LSB=0 in the process
    energy_bin = upper6         
    ;
    ; generate "highE" (i.e., LSB=1) indices from LSB 
    highE = WHERE(lsb, high_cnt)
    ;
    ; overwrite "energy_bin" wherever LSB=1
    IF (high_cnt GT 0) THEN  energy_bin[highE] = (upper6[highE])*2 + 64

    ; return "energy_bin"
    RETURN, energy_bin
END
