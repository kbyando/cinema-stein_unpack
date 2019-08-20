;------------------
; trust that users know what they are doing
;
;  formerly af_review.pro
;
; configured to examine raw ADC output of STEIN instrument (see subroutine "ADC_OUTPUT)
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

PRO ADC_OUTPUT
; for use with raw output of STEIN instrument (32-bit event record)

    ; load event-lists
    
    ; FIRST, from RAW DATA
    IF (0) THEN BEGIN
    ; Americium
    data = LOAD_EVENTLIST("~/newAm.txt")
    name_stem = "~/Am_SpecADC_det"
    ENDIF    

    IF (1) THEN BEGIN
    ; Nickel
    data = LOAD_EVENTLIST("~/newNi.txt")
    name_stem = "~/Ni_SpecADC_det"
    ENDIF

    raw_eventlist = TEMPORARY(data)
    ; STEIN data is SIGNED, correct our misinterpretation
    ; all EVCODE0 events
    r_ev0events = GET_SUBSET(raw_eventlist, 0, -1, -1)
    r_ev0index = WHERE(r_ev0events)
    ; correcting their values
    raw_eventlist[5,r_ev0index] = (raw_eventlist[5,r_ev0index] + 2L^15) MOD 2L^16

    ; so now we have one data product:
    ;   RAW_EVENTLIST (the 16-bit ADC output)

;    plot, raw_eventlist[0,r_ev0index], raw_eventlist[5,r_ev0index], PSYM=3, YRANGE=[6500,7000]
 ;   STOP

    ; select parameters
    ev_code = 0
    add = -1
    det_id_index = INDGEN(32);[18,5]
    writeFlag = 1

    ; loop over detectors
    FOR i=0, N_ELEMENTS(det_id_index) -1 DO BEGIN
        det = i
        IF (writeFlag) THEN BEGIN
            name_suffix = ".txt"
            filename = STRCOMPRESS(name_stem+String(det_id_index[i], FORMAT='(I2.2)')$
                + name_suffix)
            OPENW, /GET_LUN, unit, filename
         
            ;-----------------------------------
            ;-----------------------------------
            ;   from the RAW data
            data_index = WHERE( GET_SUBSET(raw_eventlist, ev_code[0], add[0], det_id_index[det]), raw_n)
            IF (raw_n GT 0) THEN BEGIN
                ; histogram the raw ADC values
                current_channel = HISTOGRAM_DATA(raw_eventlist, INDICES=data_index, FULLSIZE=2L^16)
                fullRange = LIndGen(2L^16)
               
                ; plot, if we like 
                PLOT, fullRange, current_channel+1, XRANGE=[1.e4,3.e4], XTITLE='ADC value (0-65535)', YTITLE="# Events (per ADC value)", PSYM=3, MIN_VALUE=1, /YLOG
                
                ; alias
                ADC_values = fullRange
                STEIN_histogram = current_channel
                
                ; print output
                FOR j=0L, N_ELEMENTS(STEIN_histogram)-1 DO BEGIN         
                    PRINTF, unit, STEIN_histogram[j]                
                ENDFOR         

                ;SAVE, ADC_values, STEIN_histogram, FILENAME="~/americium_histogram_de04.idlsav"
            ENDIF  ELSE Print, "FAIL"
            ;-----------------------------------
        FREE_LUN, unit
        ENDIF
            
    ENDFOR

END


PRO EX_EVCODE2
    ;-----------------------------------
    ; load an event-list
    eventlist = LOAD_EVENTLIST("steinbyteslog3.txt")

    ; select parameters
    ev_code = 2
    add = -1
    det_id_index = INDGEN(32)
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
