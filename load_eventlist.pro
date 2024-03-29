;+
; LOAD_EVENTLIST
; 
; AUTHOR:
;	Karl Yando
; 
; PURPOSE:
;  IDL code that reads in the ASCII event list generated by the 
;    "fsw_steinunpack.cpp" binary (e.g. "STEINBYTESLOG.txt"), and returns
;    an unlabeled event list as a data array within IDL.
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

FUNCTION LOAD_EVENTLIST, filename
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
    comment_marker = '#'
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
    data_frame = LonARR(6,data_count)
    READF, unit, data_frame

    ; free lun
    FREE_LUN, unit

;ENDFOR
; return the event-list
RETURN, data_frame
END
