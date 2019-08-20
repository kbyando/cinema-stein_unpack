;
;khu_FMtest = "KHU Flight Model test"
;
;pixels lableled 00 through 31 
;
;BLACK spectrum = Am-241
;RED spectrum = Ni-55
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
;

PRO KHU_TEST1_OVERLAID
; for use with FSW-produced output of STEIN instrument (20-bit event record)
   
    ;-----------------------------------
    ; *** EDIT THE FILENAME ***
    ;-----------------------------------
    ; load an event-list
    eventlist1 = LOAD_EVENTLIST("steinbyteslog_Americume_thresh_22_5inch_dist_4hours.txt")     ;from a C-generated ASCII list
    eventlist2 = LOAD_EVENTLIST("steinbyteslog_ion55_thresh_22_2inch_dist_3hours.txt")     ;from a C-generated ASCII list
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
    log_flag = 1
    offset = 0.1
    color1 = 0
    color2 = 250
    x_output = 0                        ; "1" to enable per-channel histogram plot to X
    ps_output = 1                       ; "1" to enable per-channel histogram plot to PS
    png_output = 0                      ; "1" to enable per-channel histogram plot to PNG
    per_channel = x_output OR ps_output OR png_output
    name_stem = 'khu_FMtest/khu_pixel'   ; (directory + name) stem for output filenames
    ;
    cumuHistogram1 = LonARR(2^7)         ; 128-elements
    current_channel1 = LonARR(2^7)         ; 128-elements
    cumuHistogram2 = LonARR(2^7)         ; 128-elements
    current_channel2 = LonARR(2^7)         ; 128-elements
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
        data_index1 = WHERE( GET_SUBSET(eventlist1, ev_code[0], add[0], det_id_index[i]) )
        data_index2 = WHERE( GET_SUBSET(eventlist2, ev_code[0], add[0], det_id_index[i]) )
        IF (data_index1[0] NE -1) THEN BEGIN
            current_channel1 = HISTOGRAM_DATA(eventlist1, INDICES=data_index1, FULL=2^7)
        ENDIF ELSE current_channel1 = log_bins * 0
        IF (data_index2[0] NE -1) THEN BEGIN
            current_channel2 = HISTOGRAM_DATA(eventlist2, INDICES=data_index2, FULL=2^7)
        ENDIF ELSE current_channel2 = log_bins * 0
        
        IF (1) THEN BEGIN
            print, det_id_index[i], " Am241 ", TOTAL(current_channel1)
            print, det_id_index[i], " Fe55 ", TOTAL(current_channel2)
            IF (tally_flag) THEN BEGIN
                cumuHistogram1 = TEMPORARY(cumuHistogram1) + current_channel1 
                cumuHistogram2 = TEMPORARY(cumuHistogram2) + current_channel2 
            ENDIF 
            ;-----------------------------------
            ; BEGIN OPTIONAL PER-CHANNEL OUTPUT (to X, PostScript, or PNG)
            ;-----------------------------------
            IF (per_channel) THEN BEGIN
                maxCount1 = MAX(current_channel1)
                maxCount2 = MAX(current_channel2)
                maxCount = maxCount1 > maxCount2
                
                IF (x_output) THEN BEGIN
                    SET_PLOT, 'X'
                    
                    ;-----------------------------------
                    PLOT, log_bins[ordered_index], current_channel1[ordered_index]+offset, $
                        TITLE="Detector Element "+string(det_id_index[i]),$
                        YLOG=log_flag, YRANGE=[offset,maxCount],$
                        XTITLE="channel number (0-192)", YTITLE="counts per energy bin", PSYM=10
                    ;-----------------------------------
                    OPLOT, log_bins[ordered_index], current_channel2[ordered_index]+offset, COLOR=color2, PSYM=10
                    ;, $
                    ;    TITLE="Detector Element "+string(det_id_index[i]),$
                    ;    YLOG=log_flag,$
                    ;    XTITLE="channel number (0-192)", YTITLE="counts per energy bin", PSYM=-4
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
                    PLOT, log_bins[ordered_index], current_channel1[ordered_index]+offset, $
                        TITLE="Detector Element "+string(det_id_index[i]),$
                        YLOG=log_flag, YRANGE=[offset,maxCount],$
                        XTITLE="channel number (0-192)", YTITLE="counts per energy bin", PSYM=10
                    ;-----------------------------------
                    OPLOT, log_bins[ordered_index], current_channel2[ordered_index]+offset, COLOR=color2, PSYM=10
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
                  PLOT, log_bins[ordered_index], current_channel[ordered_index]+offset, $
                      TITLE="Detector Element "+string(det_id_index[i]),$
                        YLOG=log_flag, YRANGE=[offset,maxCount],$
                      XTITLE="channel number (0-192)", YTITLE="counts per energy bin", PSYM=10
                  ;-----------------------------------
                  OPLOT, log_bins[ordered_index], current_channel2[ordered_index]+offset, COLOR=color2
                  ;-----------------------------------

                  WRITE_PNG, filename, TVRD()
                  SET_PLOT, 'X'
                ENDIF
            ENDIF
            ;-----------------------------------
            current_channel1 = TEMPORARY(current_channel1)*0 
            current_channel2 = TEMPORARY(current_channel2)*0 
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
    plot, log_bins[ordered_index], cumuHistogram1[ordered_index]+offset, $
        XTITLE="channel number (0-192)", YTITLE="counts per energy bin", $
        YLOG=log_flag,$
        YRANGE=[offset,MAX(cumuHistogram1)], PSYM=10
    oplot, log_bins[ordered_index], cumuHistogram2[ordered_index]+offset, COLOR=color2
    ;write_png, FILENAME_HERE
    ;
    STOP
    ;
    ; now we can specify XRANGE and YRANGE to zoom as appropriate
    plot, log_bins[ordered_index], cumuHistogram1[ordered_index], $
        XTITLE="channel number (0-192)", YTITLE="counts per energy bin", $
        XRANGE=[0,128], YRANGE=[-1,MAX(cumuHistogram1)], PSYM=10
    oplot, log_bins[ordered_index], cumuHistogram2[ordered_index], COLOR=color2
    ;-----------------------------------
    ;-----------------------------------

END 
