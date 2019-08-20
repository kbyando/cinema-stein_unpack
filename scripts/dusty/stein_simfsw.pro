;------------------
; trust that users know what they are doing
;
;  formerly stein_scripts.pro
;
; configured to compare the STEIN output from two sources (see EX_PLOT_RAW):
; 	1) flight software ("FSW"; STEIN's output through the full FPGA, PIC, TX/RX, + GSE stack)
;	2) native interface (post-processed to replicate the FSW output)
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
PRO EX_PLOT_RAW, XRANGE=x__range, YRANGE=y__range, XTITLE=x__title, YTITLE=y__title

    ; for use with raw output of STEIN instrument (32-bit event record)

    ; flow control
    simulate_fsw = 1
    plot_sim_data = 1		; plot simulated data
    plot_fsw_data = 1		; plot FSW-derived data
    plot_raw_data = 0		; plot raw STEIN data (collected via native interface)


    ; load event-lists
    
    ; FIRST, from RAW DATA
    raw_eventlist = LOAD_EVENTLIST("newAm4.txt") ; e.g., Americium spectrum
    
    ; this RAW spectrum is great, but we want to make sure our software is working correctly:
    ;  Simulate what FSW should be doing, and create a "processed RAW" dataset
    ; copy the array "RAW_eventlist", so we can edit it
    processed_raw = raw_eventlist
    IF (simulate_fsw) THEN BEGIN
        ; recreate FSW processing for EVCODE 0 events
        r_ev0events = GET_SUBSET(raw_eventlist, 0, -1, -1)
        r_ev0index = WHERE(r_ev0events)
       
        ; whereever EVCODE=0, we set ADD = -1
        processed_raw[2,r_ev0index] = -1

        ; whereever EVCODE=0, we drop 2 LSB of TIMESTAMP
        processed_raw[4,r_ev0index] = ISHFT( TEMPORARY(processed_raw[4, r_ev0index]), -2)

        ;print, MIN(processed_raw[5,*]), MAX(processed_raw[5,*])
        ; STEIN data is SIGNED, correct our misinterpretation
        raw_eventlist[5,r_ev0index] = (raw_eventlist[5,r_ev0index] + 2L^15) MOD 2L^16
        processed_raw[5,r_ev0index] = (processed_raw[5,r_ev0index] + 2L^15) MOD 2L^16

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
    fsw_eventlist = LOAD_EVENTLIST("steinbyteslog3.txt") ; FSW data product, corresponding to data collection

    ; select parameters
    ev_code = 0
    add = -1
    det_id_index = INDGEN(32)

    persheet = 1
    ps_output = 1
    name_stem = '~/FSWvSIM_ev0det'   ; (directory + name) stem for output filenames
           
    ; generate bin bounds (lower limit only)
    log_bins = LOG_UNPACK(IndGen(2^7))
    ; sort these, for use as a index on cumuHistogram
    ordered_index = SORT( log_bins )

    ; generate normalization arrays (for conversion to standard binsize)
    lower64_size = REPLICATE(256., 64)
    upper64_size = REPLICATE(256.*2., 64)
    std_size = [lower64_size, upper64_size]

    !P.MULTI=[0,1,2]
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
            IF (plot_fsw_data) THEN BEGIN
             fsw_data = GET_SUBSET(fsw_eventlist, ev_code[0], add[0], det_id_index[det])
             fsw_wholeindex = WHERE(fsw_data, fsw_wn)
            
             ; create mask for first ~2.1e5 entries (they appear to be bad)
             mask = REPLICATE(1B, N_ELEMENTS(fsw_data))
             mask_index = LINDGEN(2.1e5)
             mask[mask_index] = 0B
             ; apply the mask
             fsw_maskedindex = WHERE(fsw_data * mask, fsw_mn)
           
             current_channel_w = HISTOGRAM_DATA(fsw_eventlist, INDICES=fsw_wholeindex, FULL=2^7)
             current_channel_m = HISTOGRAM_DATA(fsw_eventlist, INDICES=fsw_maskedindex, FULL=2^7)
             print, STRCOMPRESS("DET_ID, TOTAL_CNT, GOOD_CNT, % GOOD: " + STRING(det) + ", " + STRING(fsw_wn) + ", " + STRING(fsw_mn) + "," + String(Float(fsw_mn)*100./Float(fsw_wn), FORMAT='(F7.1)'))
             ;MAX(current_channel_w)
            
             ; plot twice: once with the "whole data" scale, and again with the "masked data" scale
             ; plot 1
             ;PLOT, log_bins[ordered_index], current_channel_w[ordered_index], $
             ;                 XTITLE="keV energy", YTITLE="counts per energy bin (WHOLE)", PSYM=-4, LINESTYLE=1
             ;OPLOT, log_bins[ordered_index], current_channel_m[ordered_index], PSYM=-4
             ; plot 2

             PLOT, log_bins[ordered_index], float(current_channel_m[ordered_index])/std_size, $
                             XTITLE="keV energy (FSW; masked)", YTITLE="counts per standard bin",$
                             TITLE=STRCOMPRESS("Detector " + String(det)), PSYM=10;, /YLOG, MIN_VALUE=(1./512.)
                           ;  (normalized to ADC)", $
             ;OPLOT, log_bins[ordered_index], current_channel_w[ordered_index]+1, PSYM=-4, LINESTYLE=1
            ENDIF
            ;-----------------------------------
           

            ;-----------------------------------
            ;   from the PROCESSED_RAW data (simulated FSW)
            IF (plot_sim_data) THEN BEGIN
             ; extract the EVCODE0 subset and indices
             pro_data = GET_SUBSET(processed_raw, ev_code[0], add[0], det_id_index[det])
             pro_wholeindex = WHERE(pro_data, fsw_wn)
            
             ; histogram the data for these indices
             current_channel = HISTOGRAM_DATA(processed_raw, INDICES=pro_wholeindex, FULL=2^7)
            
             ; plot results
             PLOT, log_bins[ordered_index], float(current_channel[ordered_index])/std_size, $
                             XTITLE="keV energy (from RAW)", YTITLE="counts per standard bin",$
                             PSYM=10;, /YLOG, MIN_VALUE=(1./512.)
            ENDIF
            ;-----------------------------------
            
            
            ;-----------------------------------
            ;   from the RAW data
            IF (plot_raw_data) THEN BEGIN
             data_index = WHERE( GET_SUBSET(raw_eventlist, ev_code[0], add[0], det_id_index[det]), raw_n)
             IF (raw_n GT 0) THEN BEGIN
                current_channel = HISTOGRAM_DATA(raw_eventlist, INDICES=data_index, FULLSIZE=2L^16)
                fullRange = LIndGen(2L^16)
                PLOT, fullRange, current_channel+1, XRANGE=[1.e4,3.e4], XTITLE='ADC value (0-65535)', YTITLE="# Events (per ADC value)", PSYM=3, MIN_VALUE=1, /YLOG
                ;ADC_values = fullRange
                ;STEIN_histogram = current_channel
                ;SAVE, ADC_values, STEIN_histogram, FILENAME="~/americium_histogram_de04.idlsav"
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
        ENDIF
    ENDFOR

        ;+++    
    ; initialize empty plot window
    ;PLOT, [0,1], [0,1], /NODATA, XRANGE=[55800,57000], YRANGE=[0,10], XTITLE='ADC value (0-65535)', YTITLE='# Events (per ADC value)'
    ;PLOT, [0,1], [0,1], /NODATA, XRANGE=[4.5e4,6.e4], YRANGE=[0,800], XTITLE="ADC Value" 
    ; plot spectrum
    ;PLOT_HISTOGRAM, eventlist, EVCODE=0, ADD=0, DET_ID=0, PSYM=3, FULL=2L^16
END


PRO EX_EVCODE2
    ;-----------------------------------
    ; load an event-list
    eventlist = LOAD_EVENTLIST("steinbyteslog3.txt")

    ; select parameters
    ev_code = 2
    add = -1
    det_id_index = -1; INDGEN(32)
    ps_output = 1

    IF (ps_output) THEN BEGIN
        filename = "~/evcode2.eps"
        SET_PLOT, "PS" 
        DEVICE, COLOR=1, BITS_PER_PIXEL=8, XSIZE=5, YSIZE=7, /INCHES
        DEVICE, FILENAME=filename, ENCAPSULATED=1, PREVIEW=1
    ENDIF

    ev2_dataindex = WHERE(GET_SUBSET(eventlist, ev_code, add, det_id_index))
    print, N_ELEMENTS(ev2_dataindex)
    help, eventlist
    plot, eventlist[0,ev2_dataindex], eventlist[5, ev2_dataindex], PSYM=3;, XRANGE=[2.e5,3.2e5], YRANGE=[0,200]

    IF (ps_output) THEN BEGIN
        DEVICE, /CLOSE
        SET_PLOT, 'X'
    ENDIF
END


PRO EX_EVCODE0

    ;-----------------------------------
    ; load an event-list
    eventlist = LOAD_EVENTLIST("steinbyteslog3.txt")

    ; select parameters
    ev_code = 0
    add = -1
    det_id_index = -1; INDGEN(32)

    ev0_dataindex = WHERE(GET_SUBSET(eventlist, ev_code, add, det_id_index))
    print, N_ELEMENTS(ev0_dataindex)
    help, eventlist
    plot, eventlist[0,ev0_dataindex], eventlist[5, ev0_dataindex], PSYM=3

END



PRO EX_EVCODE0_DETS

    ;-----------------------------------
    ; load an event-list
    eventlist = LOAD_EVENTLIST("steinbyteslog3.txt")

    ; select parameters
    ev_code = 0
    add = -1
    det_id_index = INDGEN(32)
    persheet = 4
    ps_output = 1
    name_stem = '~/evcode0_dets'   ; (directory + name) stem for output filenames
                    
    !P.MULTI=[0,1,persheet]
    FOR sheet_i=0, N_ELEMENTS(det_id_index)/persheet -1 DO BEGIN
        IF (ps_output) THEN BEGIN
         SET_PLOT, 'PS'
         name_suffix = ".eps"
         filename = STRCOMPRESS(name_stem+String(det_id_index[sheet_i*persheet], FORMAT='(I2.2)')$
             + "-" + String(det_id_index[sheet_i*persheet+(persheet-1)], FORMAT='(I2.2)')+name_suffix)
         DEVICE, COLOR=1, BITS_PER_PIXEL=8, XSIZE=5, YSIZE=7, /INCHES
         DEVICE, FILENAME=filename, ENCAPSULATED=1, PREVIEW=1
        ENDIF
         
        FOR j=0, persheet-1 DO BEGIN
            det = sheet_i*persheet + j
            ;-----------------------------------
            ev0_dataindex = WHERE(GET_SUBSET(eventlist, ev_code[0], add[0], det_id_index[det]), n)
            print, N_ELEMENTS(ev0_dataindex)
            IF (n GT 0) THEN plot, eventlist[0,ev0_dataindex], eventlist[5, ev0_dataindex], PSYM=3,SYMSIZE=10, YTITLE=STRCOMPRESS("EVCODE0/DET" + String(det_id_index[det]))
            ;-----------------------------------
        ENDFOR
        
         IF (ps_output) THEN BEGIN
         DEVICE, /CLOSE
         SET_PLOT, 'X'
        ENDIF
    ENDFOR
    !P.MULTI=[0,1,1]

END

;+++



PRO EX_PLOT_FSW
; for use with FSW-produced output of STEIN instrument (20-bit event record)
   
    ;-----------------------------------
    ;-----------------------------------
    ; load an event-list
    eventlist = LOAD_EVENTLIST("steinbyteslog3.txt")
    ;eventlist = FSW_UNPACK("steinbyteslog.log")

    ; select parameters
    ev_code = 0
    add = -1
    det_id_index = INDGEN(32)
    tally_flag = 1
    cumuHistogram = LonARR(2^7)
    ;-----------------------------------
    ;-----------------------------------
   

    ; BEGIN GENERAL HISTOGRAMMING 
    
    ;-----------------------------------
    ; generate bin bounds (lower limit only)
    log_bins = LOG_UNPACK(IndGen(2^7))
    
    ; sort these, for use as a index on cumuHistogram
    ordered_index = SORT( log_bins )
    
    ;-----------------------------------
    ; print title header
    print, "DET_ID      TOTAL_CNTS"
    ;
    ; loop over det_id index
    FOR i=0, N_ELEMENTS(det_id_index)-1 DO BEGIN
        data_index = WHERE( GET_SUBSET(eventlist, ev_code[0], add[0], det_id_index[i]) )
        IF (data_index[0] NE -1) THEN BEGIN
            current_channel = HISTOGRAM_DATA(eventlist, INDICES=data_index, FULL=2^7)
            print, det_id_index[i], " ", TOTAL(current_channel)
            IF (tally_flag) THEN BEGIN
                cumuHistogram = TEMPORARY(cumuHistogram) + current_channel 
            ENDIF ELSE BEGIN
;                OPLOT, fullRange, current_channel, PSYM=psym_index[i MOD n_psym],$
;                    COLOR=color_index[i MOD n_color], _EXTRA = pass_thru
            ENDELSE
        ENDIF    
    ENDFOR
    ;-----------------------------------


    help, ordered_index, cumuHistogram, /str
    ;print,"ordered index: ", ordered_index
    ;print,"ordered bins:  ", log_bins[ordered_index]
    print,"cumulative Hist:", cumuHistogram[ordered_index]
    


    ; define a target count that we observe in histogram
    target_count = MAX(cumuHistogram)
    
    ; now send WHERE to go find out where it occurs 
    ;   (i.e., what's the corresponding data value?)
    target_eData = WHERE(cumuHistogram EQ target_count, n_Ebin_matches)
    ;print, "unsorted bin #s: ", WHERE(cumuHistogram EQ target_count)
    ;print, "sorted bin #s: ", WHERE(cumuHistogram[ordered_index] EQ target_count)
   
    print, "matches: ", n_Ebin_matches, target_eData[0]

    ; mask data for desired EV_CODE / ADD / DET_ID
    evcode0_truth = GET_SUBSET(eventlist, ev_code[0], add[0], -1)
    ;    ev_match = (data[1,*] EQ evcode[0])
    
    ; create a secondary truth array, true wherever we encounter matching data values
    targetE_truth = BytArr(N_ELEMENTS(evcode0_truth))   ;(initialized to zero)
    FOR i=0, n_Ebin_matches-1 DO BEGIN 
        ; search for matches, and if so, flip the corresponding entry to one 
        targetE_truth = TEMPORARY(targetE_truth) + (eventlist[5,*] EQ target_eData[i]) 
    ENDFOR
    print, N_ELEMENTS(evcode0_truth), N_ELEMENTS(targetE_truth)
    
    ; merge truth arrays, and extract an index 
    targetE_index = WHERE(evcode0_truth * targetE_truth, count)
    print, "number of matching entries: ", count
    print, "MAX/MIN match indices: ", MAX(targetE_index), MIN(targetE_index)
    print, ""
    print, "number of EVCODE0 events: ", TOTAL(evcode0_truth)
    length = N_ELEMENTS(evcode0_truth)
    print, "total number of events: ", length
    
    ; PLOT PORTION OF EVENTS RECEIVED
    xx = SMOOTH(FLOAT(targetE_truth),100)
    plot, xx, PSYM=3, YRANGE=[-0.1*1, 1.1*1], XRANGE=[0,length]
    print, "[0:99]-- EXPECTED,SMOOTHED,WHERE: ", TOTAL(targetE_truth[INDGEN(100)])/100., xx[50], WHERE(targetE_truth[INDGEN(100)])


    print, "INDICES: "
    ;print, targetE_index
    print, " "

    ; hrmm.. these appear to be clustered.  HOW clustered?
    ; look for any data != event
    noise = WHERE(eventlist[5,*] NE 0)
    print, "MAX/MIN noise indices: ", MAX(noise), MIN(noise), noise[1]
    
    ; the same
    ;plot, log_bins, cumuHistogram, YRANGE=[-1,MAX(cumuHistogram)], PSYM=4
    ;plot, log_bins[ordered_index], cumuHistogram[ordered_index], YRANGE=[-1,40], PSYM=-4
    ;plot, log_bins[ordered_index], cumuHistogram[ordered_index] + 1, /YLOG,  YRANGE=[1,10000], PSYM=-4
    ;
    ;
    ; and raw (unsorted; telemetered) values
    ;plot, indgen(128), cumuHistogram, YRANGE=[-1,20], PSYM=-4
;    IF (tally_flag) THEN BEGIN
;            OPLOT, fullRange, cumuHistogram, PSYM=psym_index[i MOD n_psym],$
;                COLOR=color_index[i MOD n_color], _EXTRA = pass_thru


    ; initialize empty plot window
;    PLOT, [0,1], [0,1], /NODATA, XRANGE=[0,128], YRANGE=[0,6100], XTITLE="LOG BINS"
    ;PLOT, [0,1], [0,1], /NODATA, XRANGE=[4.5e4,5.8e4], XTITLE="ADC Value (0-65535)", YTITLE="Records per Value", YRANGE=[0,250]

    ; plot spectrum(?)
 ;   PLOT_HISTOGRAM, eventlist, EVCODE=0, ADD=-1, DET_ID=-1, PSYM=-3, TALLYFLAG=1
END



PRO PLOT_COUNTS_BY_BIN
; for use with FSW-produced output of STEIN instrument (20-bit event record)
   
    ;-----------------------------------
    ; *** EDIT THE FILENAME ***
    ;-----------------------------------
    ; load an event-list
    eventlist = LOAD_EVENTLIST("steinbyteslog3.txt")     ;from a C-generated ASCII list
    ;eventlist = FSW_UNPACK("../stein_byteslog3_calibration/steinbyteslog.log")        ;directly from Brent's textdump
    ;-----------------------------------
    ;-----------------------------------

    ;-----------------------------------
    ;-----------------------------------
    ; select parameters (a "-1" indicates "no preference"/"all possible")
    ev_code = 0                         ; we want EVCODE0
    add = -1                            ; no preference
    det_id_index = IndGen(32)           ; all detectors
    ; NOTE: if you wanted some subset of detectors, you would indicate that with
    ;  their IDs (e.g., "det_id_index=2" or "det_id_index=[2,3,5,7,10]")
    tally_flag = 1                      ; "1" to make a cumulative histogram from all DET_ID
    x_output = 1                        ; "1" to enable per-channel histogram plot to X
    ps_output = 0                       ; "1" to enable per-channel histogram plot to PS
    png_output = 0                      ; "1" to enable per-channel histogram plot to PNG
    per_channel = x_output OR ps_output OR png_output
    name_stem = '~/detA'   ; (directory + name) stem for output filenames
    ;
    cumuHistogram = LonARR(2^7)         ; 128-elements
    current_channel = LonARR(2^7)         ; 128-elements
    ;-----------------------------------
   

    ;-----------------------------------
    ; BEGIN GENERAL HISTOGRAMMING 
    ;-----------------------------------
    ; generate bin bounds (lower limit only)
    log_bins = LOG_UNPACK(IndGen(2^7))
    
    ; sort these, for use as a index on cumuHistogram
    ordered_index = SORT( log_bins )
    
    ; print title header
    print, "DET_ID      TOTAL_CNTS"
    ;
    ; loop over det_id index
    FOR i=0, N_ELEMENTS(det_id_index)-1 DO BEGIN
        data_index = WHERE( GET_SUBSET(eventlist, ev_code[0], add[0], det_id_index[i]) )
        IF (data_index[0] NE -1) THEN BEGIN
            current_channel = HISTOGRAM_DATA(eventlist, INDICES=data_index, FULL=2^7)
            print, det_id_index[i], " ", TOTAL(current_channel)
            IF (tally_flag) THEN BEGIN
                cumuHistogram = TEMPORARY(cumuHistogram) + current_channel 
            ENDIF 
            ;-----------------------------------
            ; BEGIN OPTIONAL PER-CHANNEL OUTPUT (to X, PostScript, or PNG)
            ;-----------------------------------
            IF (per_channel) THEN BEGIN
                IF (x_output) THEN BEGIN
                    SET_PLOT, 'X'
                    
                    ;-----------------------------------
                    PLOT, log_bins[ordered_index], current_channel[ordered_index], $
                        XTITLE="keV energy", YTITLE="counts per energy bin", PSYM=-4
                    ;-----------------------------------
                    
                    WAIT, 1
                ENDIF
                IF (ps_output) THEN BEGIN
                    SET_PLOT, 'PS'
                    name_suffix = ".eps"
                    filename = STRCOMPRESS(name_stem+String(det_id_index[i], $
                        FORMAT='(I2.2)')+name_suffix)
                    DEVICE, COLOR=1, BITS_PER_PIXEL=8
                    DEVICE, FILENAME=filename, ENCAPSULATED=1, PREVIEW=1
                    
                    ;-----------------------------------
                    PLOT, log_bins[ordered_index], current_channel[ordered_index], $
                        XTITLE="keV energy", YTITLE="counts per energy bin", PSYM=-4
                    ;-----------------------------------

                    DEVICE, /CLOSE
                    SET_PLOT, 'X'
                ENDIF
                IF (png_output) THEN BEGIN

                  SET_PLOT, 'Z'
                  name_suffix = ".png"
                  filename = STRCOMPRESS(name_stem+String(det_id_index[i], $
                      FORMAT='(I2.2)')+name_suffix)
                  DEVICE, SET_RESOLUTION=[1280,1024]
                  
                  ;-----------------------------------
                  PLOT, log_bins[ordered_index], current_channel[ordered_index], $
                      XTITLE="keV energy", YTITLE="counts per energy bin", PSYM=-4
                  ;-----------------------------------

                  WRITE_PNG, filename, TVRD()
                  SET_PLOT, 'X'
                ENDIF
            ENDIF
            ;-----------------------------------
            current_channel = TEMPORARY(current_channel)*0 
        ENDIF    
    ENDFOR
    ;-----------------------------------
    ;-----------------------------------
    ; *** EDIT THESE ***
            
    ;-----------------------------------
    ; "log_bins" are just the data values 0-127 mapped to keV energies
    ; "cumuHistogram" is the cumulative histogram of whichever detectors 
    ;           you're looking at (defined by "det_d_index")
    ; "ordered_index" puts "log_bins" in ascending order
    ; ---
    ; first plot the whole thing
    plot, log_bins[ordered_index], cumuHistogram[ordered_index], $
        XTITLE="keV energy", YTITLE="counts per energy bin", $
        YRANGE=[-1,MAX(cumuHistogram)], PSYM=-4
    ;write_png, FILENAME_HERE
    ;
    STOP
    ;
    ; now we can specify XRANGE and YRANGE to zoom as appropriate
    plot, log_bins[ordered_index], cumuHistogram[ordered_index], $
        XTITLE="keV energy", YTITLE="counts per energy bin", $
        XRANGE=[0,128], YRANGE=[-1,40], PSYM=-4
    ;-----------------------------------
    ;-----------------------------------

END 
