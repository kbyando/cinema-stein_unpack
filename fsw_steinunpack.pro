;+
; FSW_STEINUNPACK
; 
; AUTHOR:
;	Karl Yando
; 
; PURPOSE:
;	Collection of functions to unpack CINEMA's flight software
;  datastream (received via GSE), and return an unlabeled event list
;  as a data array within IDL.
;
; USAGE:
;   < to be written >	
;
; MODIFICATION HISTORY:
;   (formerly FSW_UNPACK.PRO)
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
;-

FUNCTION READ_FSW_ASCII, filename
; reads a Flight Software (FSW) produced ASCII file of downlink packet bytes
; instantiate variables
data_file = ""
file_count = 0

IF FILE_TEST(filename, /READ, /REGULAR) THEN BEGIN
    data_file = filename        ; (assume good data)
    file_count = 1
ENDIF ; else we can examine the contents of a directory, for instance

;FOR i=0, file_count-1 DO BEGIN
    OPENR, /GET_LUN, unit, data_file    ;[i]
    ; probably don't need to call FSTAT..

    ; auto read-in
    comment_marker = '#'        ; (empty string)
    start_position = 0L
    data_count = 0L
    str=""

    ; peruse contents (no copy)
    WHILE (~EOF(unit)) DO BEGIN
        READF, unit, str                ;(read-in line)
        ; assume that comments and header occur only at the begin
        IF STRCMP(str,comment_marker,1) THEN BEGIN ;(comment on this line)
            POINT_LUN, -unit, byteID    ;(get byteID)
            start_position = byteID     ;(store byteID)
            ; we can skip straight to the end of this line now
        ENDIF ELSE ++data_count         ;(increment data_count)
    ENDWHILE

    ; instantiate our data array
    ; (frame_number / EVCODE / ADD / DET_ID / TIMESTAMP / DATA)
    
    ; copy in data
    POINT_LUN, unit, start_position
    string_data = StrARR(data_count)
    READF, unit, string_data

    ; free lun
    FREE_LUN, unit

;ENDFOR
RETURN, string_data
END


FUNCTION hex_extract, string_data
; extracts numerical data from hex-formatted ASCII strings
    n_lines = N_ELEMENTS(string_data)
    line_test = BytArr(n_lines)
    ; test for blank lines
    FOR i=0, n_lines-1 DO BEGIN
        line_test[i] = STRCMP('0x', string_data[i], 2)
        ; true if we have formatted hex data
        ; false otherwise
    ENDFOR 
    line_index = WHERE(line_test, n_lines)
    print, n_lines
    
    ; instantiate + fill hex array
    raw_hex = LonArr(n_lines, 514)
    FOR i=0, n_lines-1 DO BEGIN
        hexbytes = STRSPLIT(string_data[line_index[i]], " ", /EXTRACT)
        n_bytes = N_ELEMENTS(hexbytes)
        FOR j=0, n_bytes-1 DO BEGIN
            length = STRLEN(hexbytes[j])
            raw_hex[i,j] = hex2dec( STRMID(hexbytes[j], 2, length-3), /QUIET)
        ENDFOR
    ENDFOR
    
    RETURN, raw_hex
END

FUNCTION PARSE_FSW_HEX, hex_data
; parses the bytes in a 512-byte FSW-produced data downlink frame 
    ; gather data
    array_info = SIZE(hex_data)
    array_depth = array_info[1]

    ; create storage arrays
    cssds = "not included"      ;6-bytes
    stein_header        = BytArr(array_depth,1) ;1-byte (0xAF)
    time_stamp          = BytArr(array_depth,6) ;6-bytes (mo / dy / hr / min / sec / fracsec)
    stein_data          = BytArr(array_depth,495);495-bytes (198 events * 20 bits / event)
    housekeeping        = BytArr(array_depth,8);8-bytes
    spare               = BytArr(array_depth,4);4-bytes
    ; NOTE: 1+6+495+8+4 = 514 (observed)
    
    ; create slice indices
    depth = LIndGen(array_depth)
    time_index = IndGen(6)+1
    data_index = IndGen(495)+(1+6)
    hkpg_index = IndGen(8) + (1+6+495)
    spare_index = IndGen(4) + (1+6+495+8)

    ; slice arrays
    stein_header = hex_data[*, 0]
    time_stamp = hex_data[*, time_index] 
    stein_data = hex_data[*, data_index ]
    hkpg_data = hex_data[*, hkpg_index ]
    spare = hex_data[*, spare_index]

    data_structure = {NPACKETS:array_depth, CSSDS:cssds, STEINHEADER:stein_header, TIMESTAMP:time_stamp, STEINDATA:stein_data, HKPG:hkpg_data, UNUSED:spare}
    RETURN, data_structure    
END


FUNCTION extract_events, stein_data
; extracts individual events from a FSW-produced block of STEIN data
    ; STEIN data is reported in a 495-byte block, comprising 198 events of 20 bits each
    
    ; so.. every 5 bytes gives us 2 complete STEIN events.  
    increment = 5       ;(bytes)
    n_events = 198
    working_bytes = LonArr(increment)
    event_log = LonArr(n_events)     ;(198 events)
    FOR i=0, (n_events/2)-1 DO BEGIN
        ; grab 5 bytes
        working_bytes = stein_data[IndGen(increment) + i*increment]
        ;print, i, working_bytes
        event1 = ISHFT( (working_bytes[2] AND 15b), 16) + ISHFT(working_bytes[1],8) + working_bytes[0]
        event2 = ISHFT( working_bytes[4], 12) + ISHFT(working_bytes[3], 4) + ISHFT(working_bytes[2], -4)
        event_log[2*i]          = event1
        event_log[2*i+1]        = event2
    ENDFOR
    RETURN, event_log
END


FUNCTION parse_eventreport, stein_event
; parses an individual STEIN event on the basis of EVCODE

    evCode = ISHFT(stein_event,-18)     ; upper 2 bits
    CASE evCode OF
        0: BEGIN        ;(i.e., is a data packet)
            ; no ADD bit (0 bits; all bits dropped)
            add = -1
            ; DET_ID (5 bits)
            det_id = ISHFT(stein_event, -20 + (2+5)) AND 31b
            ; TIMESTAMP (6 bits; 2 LSB dropped)
            time_stamp = ISHFT(stein_event, -20 + (2+5+6)) AND 63b
            ; DATA (7 bits; 9 bits dropped via log-binning)
            data = ISHFT(stein_event, -20 + (2+5+6+7)) AND 127b
            END
        1: BEGIN        ;(i.e., Sweep checksum/# of triggers per second)
            ; no ADD bit (0 bits; all bits dropped)
            add = -1
            ; no DET_ID bits (0 bits; all bits dropped)
            det_id = -1
            ; TIMESTAMP (6 bits; 2 MSB dropped)
            time_stamp = ISHFT(stein_event, -20 + (2+6)) AND 63b
            ; DATA (12 bits; 4 lower bits dropped)
            data = ISHFT(stein_event, -20 + (2+6+12)) AND 4095L
            END
        2: BEGIN        ;(i.e., Sweep checksum/# of events per second)
            ; no ADD bit (0 bits; all bits dropped)
            add = -1
            ; no DET_ID bits (0 bits; all bits dropped)
            det_id = -1
            ; TIMESTAMP (6 bits; 2 MSB dropped)
            time_stamp = ISHFT(stein_event, -20 + (2+6)) AND 63b
            ; DATA (12 bits; 4 lower bits dropped)
            data = ISHFT(stein_event, -20 + (2+6+12)) AND 4095L
            END
        3: BEGIN
            ; ADD bit (1 bit; no bits dropped)
            add = ISHFT(stein_event, -20 + (2+1)) AND 1b
            IF (add EQ 0) THEN BEGIn ; EVCODE3 TYPE 1 (noise event)
                ; DET_ID bits (1 bit; 4 MSB dropped)
                det_id = ISHFT(stein_event, -20 + (2+1+1)) AND 1b
                ; TIMESTAMP (0 bits; all bits dropped)
                time_stamp = -1
                ; DATA (16 bits; no bits dropped)
                data = stein_event AND 65535L
            ENDIF ELSE IF (add EQ 1) THEN BEGIN ; EVCODE3 TYPE 2 (status event)
                ; DET_ID bits (0 bits; all bits dropped)
                det_id = -1
                ; TIMESTAMP (8 bits; no bits dropped)
                time_stamp = ISHFT(stein_event, -20 + (2+1+8)) AND 255b
                ; DATA (9 bits; 7 MSB dropped)
                data = stein_event AND 511
            ENDIF ELSE Print, "Error! (INVALID ADD!)"
            END
        ELSE: Print, "Error! (INVALID EVCODE!)" 
    ENDCASE

    RETURN, {EVCODE:evCode, ADD:add, DETID:det_id, TIMESTAMP:time_stamp, STEINDATA:data}
END


FUNCTION FSW_UNPACK, filename
; prepares a STEIN "event-list" (indexed by absolute event number over all 
;  packets) from an ASCII text-dump of FSW-produced downlink data packets
    str_data = READ_FSW_ASCII(filename)  ; loads data to a string array 
    hex_data = HEX_EXTRACT(str_data)            ; extracts the hex contents
    packet_struct = PARSE_FSW_HEX(hex_data)         ; parses downlink packet structure

    n_packets = packet_struct.NPACKETS
    n_events = 198                              ;(number events per packet)

    all_evcode  = IntArr(n_packets, n_events)   ;(max 2 bits; SIGNED)
    all_add     = IntArr(n_packets, n_events)   ;(max 1 bit; SIGNED
    all_detID   = IntArr(n_packets, n_events)   ;(max 5 bits; SIGNED)
    all_time    = IntArr(n_packets, n_events)   ;(max 8 bits; SIGNED)
    all_data    = LonArr(n_packets, n_events)   ;(max 16 bits; SIGNED)

    ; we can now extract event data from each of the science packets
    FOR i=0L,n_packets-1 DO BEGIN                  ;(loop over packets) 
        stein_events = EXTRACT_EVENTS(packet_struct.steindata[i,*])
        ;print, stein_events[0], stein_events[1]
        ;print, i, N_ELEMENTS(stein_events)
        FOR j=0,n_events-1 DO BEGIN             ;(loop over events)
            eventreport = PARSE_EVENTREPORT(stein_events[j])
            all_evcode[i,j]     = eventreport.evcode
            all_add[i,j]        = eventreport.add
            all_detID[i,j]      = eventreport.detid
            all_time[i,j]       = eventreport.timestamp
            all_data[i,j]       = eventreport.steindata
        ENDFOR
    ENDFOR

    ; or merge packet_number "i" and packet_record "j" to create
    ;  a single data array indexed by "event_number"
    n_allEvents = Long(n_packets)*Long(n_events);(total number of events we have)
    evn_index = LIndGen(n_allEvents)            ;(event number index)
    ;
    ; instantiate our data array
    ; (event_number / EVCODE / ADD / DET_ID / TIMESTAMP / DATA)
    data_array = LonArr(6, n_allEvents) 
    ;
    ; flatten arrays, and copy in data as columns
    data_array[0,evn_index] = REFORM(evn_index, n_allEvents)
    data_array[1,evn_index] = REFORM(TRANSPOSE(all_evcode), n_allEvents)
    data_array[2,evn_index] = REFORM(TRANSPOSE(all_add), n_allEvents)
    data_array[3,evn_index] = REFORM(TRANSPOSE(all_detID), n_allEvents)
    data_array[4,evn_index] = REFORM(TRANSPOSE(all_time), n_allEvents)
    data_array[5,evn_index] = REFORM(TRANSPOSE(all_data), n_allEvents)

    ; return this event-list
    RETURN, data_array
END

