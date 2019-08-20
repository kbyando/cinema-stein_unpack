;------------------
; comparison of CINEMA1 32-bit and 20-bit data records (Berkeley Flight Unit)
;
; berk_cinema1 - "UC Berkeley Flight Model #1 (CINEMA 1)"
; 
; BLACK spectrum = Am-241 calibration spectrum, obtained via FSW/GSEOS before delivery
;
; RED spectrum = Am-241 high-resolution (16-bit) calibration spectrum, obtained
;     directly from STEIN during detector evaluation, and post-processed to 
;     7-bits of log-binned energy resolution for purposes of comparison
;
;
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
;------------------
PRO BERK_CINEMA1, XRANGE=x__range, YRANGE=y__range, XTITLE=x__title, YTITLE=y__title
; for use with raw output of STEIN instrument (32-bit event record)

    ; load event-lists
    ; FIRST, from RAW DATA
    data = LOAD_EVENTLIST("Am40V.txt")
        
    raw_eventlist = TEMPORARY(data)
    ; this RAW spectrum is great, but we want to make sure our software is working correctly:
    ;  Simulate what FSW should be doing, and create a "processed RAW" dataset
    ; copy the array "RAW_eventlist", so we can edit it
    processed_raw = raw_eventlist
    IF (1) THEN BEGIN
        ; recreate FSW processing for EVCODE 0 events
        r_ev0events = GET_SUBSET(raw_eventlist, 0, -1, -1)
        r_ev0index = WHERE(r_ev0events)
       
        ; whereever EVCODE=0, we set ADD = -1
        processed_raw[2,r_ev0index] = -1

        ; whereever EVCODE=0, we drop 2 LSB of TIMESTAMP
        processed_raw[4,r_ev0index] = ISHFT( TEMPORARY(processed_raw[4, r_ev0index]), -2)

        ;print, MIN(processed_raw[5,*]), MAX(processed_raw[5,*])
        ; STEIN data is SIGNED (there used to be a bug here)

        ; drop the lower 8 bits
        upper8bits = ISHFT( processed_raw[5, r_ev0index], -8)
        print, "MIN/MAX_UPPER8", MIN(upper8bits), MAX(upper8bits)
        
        ; bin by value
        lt64 = WHERE(upper8bits LT 64, n_lt64)
        lt128  = WHERE( (upper8bits GE 64) AND (upper8bits LT 128), n_lt128)
        lt192  = WHERE( (upper8bits GE 128) AND (upper8bits LT 192), n_lt192)
        ge192  = WHERE( (upper8bits GE 192), n_ge192)
        help, lt64, lt128, lt192, ge192
        
        ; log compress
        IF (n_lt64 GT 0) THEN processed_raw[5,r_ev0index[lt64]] = $
            ISHFT(upper8bits[lt64] AND 63b, 1)
        IF (n_lt128 GT 0) THEN processed_raw[5,r_ev0index[lt128]] = $
            (upper8bits[lt128] AND 62b) OR 1b
        IF (n_lt192 GT 0) THEN processed_raw[5,r_ev0index[lt192]] = $
            (upper8bits[lt192] AND 62b) OR 65b
        IF (n_ge192 GT 0) THEN processed_raw[5,r_ev0index[ge192]] = 127b
       
    ENDIF    

    ; so now we have two data products:
    ;   RAW_EVENTLIST (the 16-bit ADC output)
    ;   PROCESSED_RAW (for EVCODE0, the RAW_EVENTLIST data washed down to FSW resolution)

    ; import a new dataset: FSW DATA
    fsw_eventlist = LOAD_EVENTLIST("steinbyteslog3.txt")

    ; select parameters
    ev_code = 0
    add = -1
    det_id_index = INDGEN(32)

    persheet = 1
    ps_output = 1
    scaling = 1.
    offset = 0.1 
    name_stem = 'berk_cinema1/cin1_pixel'   ; (directory + name) stem for output filenames
           
    ; generate bin bounds (lower limit only)
    log_bins = LOG_UNPACK(IndGen(2^7))
    ; sort these, for use as a index on cumuHistogram
    ordered_index = SORT( log_bins )

    ; generate normalization arrays (for conversion to standard binsize)
    ; lower64_size = REPLICATE(256., 64)
    ; upper64_size = REPLICATE(256.*2., 64)
    ;std_size = [lower64_size, upper64_size]

    !P.MULTI=[0,1,1]
    ; loop over sheet elements (and detectors)
    FOR sheet_i=0, N_ELEMENTS(det_id_index)/persheet -1 DO BEGIN
        IF (ps_output) THEN BEGIN
         SET_PLOT, 'PS'
         name_suffix = ".eps"
         filename = STRCOMPRESS(name_stem+String(det_id_index[sheet_i*persheet], FORMAT='(I2.2)')$
             + "-" + String(det_id_index[sheet_i*persheet+(persheet-1)], FORMAT='(I2.2)')+name_suffix)
         DEVICE, COLOR=1, BITS_PER_PIXEL=8, XSIZE=7., YSIZE=10., /INCHES
         DEVICE, FILENAME=filename, ENCAPSULATED=1, PREVIEW=1
        ENDIF
         
        FOR j=0, persheet-1 DO BEGIN
            det = sheet_i*persheet + j
            ;-----------------------------------
            ;   from the FSW data
            IF (1) THEN BEGIN
             fsw_data = GET_SUBSET(fsw_eventlist, ev_code[0], add[0], det_id_index[det])
             fsw_wholeindex = WHERE(fsw_data, fsw_wn)
            
             ; create mask for first ~2.1e5 entries (they appear to be bad)
             mask = REPLICATE(1B, N_ELEMENTS(fsw_data))
             mask_index = LINDGEN(2.1e5)
             mask[mask_index] = 0B
             ; apply the mask
             fsw_maskedindex = WHERE(fsw_data * mask, fsw_mn)
           
             current_channel_w = HISTOGRAM_DATA(fsw_eventlist, INDICES=fsw_wholeindex, FULL=2^7)        ; whole histogram
             current_channel_m = HISTOGRAM_DATA(fsw_eventlist, INDICES=fsw_maskedindex, FULL=2^7)       ; masked histogram
             print, STRCOMPRESS("DET_ID, TOTAL_CNT, GOOD_CNT, % GOOD: " + STRING(det) + ", " + STRING(fsw_wn) + ", " + STRING(fsw_mn) + "," + String(Float(fsw_mn)*100./Float(fsw_wn), FORMAT='(F7.1)'))
             ;MAX(current_channel_w)
            
             ; plot twice: once with the "whole data" scale, and again with the "masked data" scale
             ; plot 1
             ;PLOT, log_bins[ordered_index], current_channel_w[ordered_index], $
             ;                 XTITLE="keV energy", YTITLE="counts per energy bin (WHOLE)", PSYM=-4, LINESTYLE=1
             ;OPLOT, log_bins[ordered_index], current_channel_m[ordered_index], PSYM=-4
             ; plot 2

             PLOT, log_bins[ordered_index], float(current_channel_m[ordered_index])+offset, $
                             XTITLE="channel number (0-192)", YTITLE="counts per bin",$
                             TITLE=STRCOMPRESS("CIN1 Pixel #" + String(det)), PSYM=10, /YLOG;, MIN_VALUE=(1./512.)
                           ;  (normalized to ADC)", $
             ;OPLOT, log_bins[ordered_index], current_channel_w[ordered_index]+1, PSYM=-4, LINESTYLE=1
            ENDIF
            ;-----------------------------------
           

            ;-----------------------------------
            ;   from the PROCESSED_RAW data (simulated FSW)
            IF (1) THEN BEGIN
             ; extract the EVCODE0 subset and indices
             pro_data = GET_SUBSET(processed_raw, ev_code[0], add[0], det_id_index[det])
             pro_wholeindex = WHERE(pro_data, fsw_wn)
            
             ; histogram the data for these indices
             current_channel = HISTOGRAM_DATA(processed_raw, INDICES=pro_wholeindex, FULL=2^7)
            
             ; plot results
             OPLOT, log_bins[ordered_index], float(current_channel[ordered_index])*scaling + offset, $
                             PSYM=10, COLOR=250
                             ;XTITLE="keV energy (from RAW)", YTITLE="counts per standard bin",$
                             ;PSYM=10;, /YLOG, MIN_VALUE=(1./512.)
            ENDIF
            ;-----------------------------------
            
            
            ;-----------------------------------
            ;   from the RAW data
            IF (0) THEN BEGIN
             data_index = WHERE( GET_SUBSET(raw_eventlist, ev_code[0], add[0], det_id_index[det]), raw_n)
             IF (raw_n GT 0) THEN BEGIN
                current_channel = HISTOGRAM_DATA(raw_eventlist, INDICES=data_index, FULLSIZE=2L^16)
                fullRange = LIndGen(2L^16)
                PLOT, fullRange, current_channel+1, XRANGE=[1.e4,3.e4], XTITLE='ADC value (0-65535)', YTITLE="# Events (per ADC value)", PSYM=3, MIN_VALUE=1, /YLOG
                ;ADC_values = fullRange
                ;STEIN_histogram = current_channel
                ;SAVE, ADC_values, STEIN_histogram, FILENAME="~/Desktop/americium_histogram_de04.idlsav"
             ENDIF ELSE BEGIN
                PLOT, [0,1], [0,1], /NODATA, XRANGE=[4.0e4,6.0e4], YRANGE=[0,approx_height], XTITLE='ADC value (0-65535)', YTITLE='# Events (per ADC value)'
                ;PLOT_HISTOGRAM, RAW_eventlist, EVCODE=0, ADD=-1, DET_ID=det, PSYM=3, FULL=2L^16
             ENDELSE 
            ENDIF
            ;-----------------------------------
            

            ;PLOT, [0,1], [0,1], /NODATA, XRANGE=[0,192], YRANGE=[0,10000], XTITLE='keV energy (maybe)', YTITLE='# Events (per log-bin)'
            ;PLOT_HISTOGRAM, RAW_eventlist, EVCODE=0, ADD=-1, DET_ID=det, PSYM=3, FULL=2L^16
            ;raw_dataindex = WHERE(GET_SUBSET(RAW_eventlist, ev_code[0], add[0], det_id_index[det]), raw_n)
            ;print, "DET: ", det, " CNT: ", raw_n, fsw_n
            ;IF (n_raw GT 0) THEN plot, RAW_eventlist[0,raw_dataindex], RAW_eventlist[5, raw_dataindex], PSYM=3,SYMSIZE=10, YTITLE=STRCOMPRESS("RAWEV0/DET" + String(det_id_index[det])) ELSE PLOT, [0,1], [0,1]
            ;IF (n_fsw GT 0) THEN plot, FSW_eventlist[0,fsw_dataindex], FSW_eventlist[5, fsw_dataindex], PSYM=3,SYMSIZE=10, YTITLE=STRCOMPRESS("FSWEV0/DET" + String(det_id_index[det]))
            ;-----------------------------------
        ENDFOR
       

         IF (ps_output) THEN BEGIN
            DEVICE, /CLOSE
            SET_PLOT, 'X'
        ENDIF ELSE WAIT, 2
    ENDFOR

        ;+++    
    ; initialize empty plot window
    ;PLOT, [0,1], [0,1], /NODATA, XRANGE=[55800,57000], YRANGE=[0,10], XTITLE='ADC value (0-65535)', YTITLE='# Events (per ADC value)'
    ;PLOT, [0,1], [0,1], /NODATA, XRANGE=[4.5e4,6.e4], YRANGE=[0,800], XTITLE="ADC Value" 
    ; plot spectrum
    ;PLOT_HISTOGRAM, eventlist, EVCODE=0, ADD=0, DET_ID=0, PSYM=3, FULL=2L^16
END

