//
// fsw_steinunpack.cpp -- C++ code to produce an ASCII event list from Brent's
// ASCII text dump of the FSW data.  Compiles with g++.  If compiled 
// binary has name "fsw_steinunpack", then usage on a UNIX machine is:
//
//    ./fsw_steinunpack STEINBYTESLOG.log > STEINBYTESLOG.txt
//
// where "STEINBYTESLOG.log" is the name and path of the ASCII hex-bytes 
//  text dump file, and "STEINBYTESLOG.txt" is the name and path of the
//  output file, to which an ASCII event list will be written.
//
//
// MODIFICATION HISTORY:
//   (formerly fsw_unpack.cpp)
//
//
// Copyright 2013 Karl Yando
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#include <fstream>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <algorithm>
#include <vector>
using namespace std;


// function to tokenize a string according to some delimited, 
// taken from: <http://www.oopweb.com/CPP/Documents/CPPHOWTO/
//                      Volume/C++Programming-HOWTO-7.html> 
void Tokenize(const string& str,
                        vector<string>& tokens,
                        const string& delimiters = " ")
{
    // Skip delimiters at beginning.
    string::size_type lastPos = str.find_first_not_of(delimiters, 0);
    // Find first "non-delimiter".
    string::size_type pos     = str.find_first_of(delimiters, lastPos);

    while (string::npos != pos || string::npos != lastPos)
    {
        // Found a token, add it to the vector.
        tokens.push_back(str.substr(lastPos, pos - lastPos));
        // Skip delimiters.  Note the "not_of"
        lastPos = str.find_first_not_of(delimiters, pos);
        // Find next "non-delimiter"
        pos = str.find_first_of(delimiters, lastPos);
    }
}

// function to extract events from the 495-byte STEIN data block
void ExtractEvents(uint8_t stein_frame[], uint32_t event_log[]) {
    // 495-byte block, comprising 198 events of 20 bits each
    // So.. every 5 bytes gives us 2 complete STEIN events
    uint16_t increment = 5;             // (bytes)
    uint16_t n_events = 198;            // (events)
    uint32_t working_bytes [increment];  // 5-byte chunk to work with 

    // storage arrays (16-bit should be ok)
    uint32_t event1, event2;            // for processing
    
    for (uint16_t i=0; i <= ((n_events/2) -1); i++) {
        // populate "working_bytes"
        for (uint16_t j=0; j < increment; j++) {
            working_bytes[j] = stein_frame[j + i*increment];
        }
        // split, bitshift, and re-construct event values
        event1 = ((working_bytes[2] & 15L) << 16) + (working_bytes[1] << 8) + (working_bytes[0]);
        event2 = (working_bytes[4] << 12) + (working_bytes[3] << 4) + (working_bytes[2] >> 4);
        event_log[2*i] = event1;        // place in event_log
        event_log[2*i + 1] = event2;    //      """
    }
    // no return value needed, as we're modifying event_log itself (we hope!)
}

void Parse_EventReport(uint32_t stein_event, int16_t &evcode, int16_t &add, int16_t &det_id, int16_t &time_stamp, int32_t &event_data) {
   evcode = stein_event >> 18;
   switch (evcode) {
    case 0:     // (i.e., is a data packet)
        // no ADD bit (0 bits; all bits dropped)
        add=-1;
        // DET_ID (5 bits)
        det_id = (stein_event >> (20 - (2+5))) & 31;
        // TIMESTAMP (6 bits; 2 LSB dropped)
        time_stamp = (stein_event >> (20 - (2+5+6))) & 63;
        // EVENT_DATA (7 bits; 9 bits dropped via log-binning)
        event_data = (stein_event >> (20 - (2+5+6+7))) & 127;
        break;
    case 1:     // (i.e., Sweep checksum/# of triggers per second)
        // no ADD bit (0 bits; all bits dropped)
        add = -1;
        // no DET_ID bits (0 bits; all bits dropped)
        det_id = -1;
        // TIMESTAMP (6 bits; 2 MSB dropped)
        time_stamp = (stein_event >> (20 - (2+6))) & 63;
        // DATA (12 bits; 4 lower bits dropped)
        event_data = (stein_event >> (20 - (2+6+12))) & 4095;
       break;
    case 2:     // (i.e., Sweep checksum/# of events per second)
        // no ADD bit (0 bits; all bits dropped)
        add = -1;
        // no DET_ID bits (0 bits; all bits dropped)
        det_id = -1;
        // TIMESTAMP (6 bits; 2 MSB dropped)
        time_stamp = (stein_event >> (20 - (2+6))) & 63;
        // DATA (12 bits; 4 lower bits dropped)
        event_data = (stein_event >> (20 - (2+6+12))) & 4095;
        break;
    case 3: 
        // ADD bit (1 bit; no bits dropped)
        add =(stein_event >> (20 - (2+1))) & 1;
        if (add == 0) { // EVCODE3 TYPE 1 (noise event)
            // DET_ID bits (1 bit; 4 MSB dropped)
            det_id = (stein_event >> (20 - (2+1+1))) & 1;
            // TIMESTAMP (0 bits; all bits dropped)
            time_stamp = -1;
            // DATA (16 bits; no bits dropped)
            event_data = stein_event & 65535L;
        } else if (add == 1) {// EVCODE3 TYPE 2 (status event)
            // DET_ID bits (0 bits; all bits dropped)
            det_id = -1;
            // TIMESTAMP (8 bits; no bits dropped)
            time_stamp = (stein_event >> (20 - (2+1+8))) & 255;
            // DATA (9 bits; 7 MSB dropped)
            event_data = stein_event & 511;
        } else {
            cout << "Error! (INVALID ADD!)" << endl;
        }
        break;
    default:
        cout << "Error! (INVALID EVCODE!)" << endl;
        add = -1;
        det_id = -1;
        time_stamp = -1;
        event_data = -1;
      break; 
   }

}



// procedure to read in and parse ASCII text dumps of CINEMA
//      flight software output bytes
int main(int argc, char *argv[]) {      
    // optional command-line argument "filename"
    char *fileName;

    // parse command-line arguments
    if (argc == 1){             // filename not specified; prompt user
        // BROKEN - the user prompted contents of FILENAME fail to work
        string receiver;        // initialize a string to receive input
        // prompt for a data file
        cout << "Welcome to STEIN_EXTRACT!  Please input file name: ";
        cin >> receiver;
        // copy elements of string to char array
        //char input[receiver.size() + 1];
        //for (int i=0; i<receiver.size(); i++) {
        //    input[i] = receiver[i];
        //}
        //input[receiver.size()] = '\0';
        //fileName = &(input[0]);
        char input[receiver.size() + 1];
        //input = (receiver.c_str);
        //cout << input;
        //fileName = &(receiver.c_str[0]); //&(input[0]);
        //cout << fileName << "|";
        cout << "\n";
    } else if (argc ==2 ) {     // argv[0] specified (assumed to be a filename)
        cout << "# usage: " << argv[0] << " <data file>\n";
        fileName = argv[1];
        cout << "# " << fileName << "\n";
    } // ignore any subsequent arguments

    // initialize variables for data import
    struct stat results;
    unsigned int binary_len = 0;

    // attempt to get file size, in bytes
    if (stat(fileName, &results) == 0) {
        // success; copy result to variable "binary_len"
        binary_len = results.st_size;
    } else {
        // file open FAILED
        cout << "Invalid file name / path: read failed!\n";
        return 0;
    }

    // helper variables
    uint32_t line_cnt = 0L;
    string ascii_line;          // temporary
   
    // open file to take a "peek" inside
    ifstream asciiDataFile (fileName, ios::in); 
    if (asciiDataFile.is_open()) {
        while (asciiDataFile.good()) {
            // read in a line, and see whether it is empty
            getline(asciiDataFile,ascii_line);

            if (ascii_line.length() > 1) {
                line_cnt++;
                // cout << line_cnt << " " << ascii_line.length() << endl;
            }   // else, blank line
        }
        cout << "# packet count (line_cnt): " << line_cnt << "\n";
        asciiDataFile.close();
    } else {
        // file open FAILED
        cout << "Invalid file name / path: read failed!\n";
        return 0;
    }

    // DATA PACKET PARAMETERS
    uint16_t    packet_size = 512;      // size (BYTES) of one packet of FSW data
    // NOTE: the packet *usually* occupies 518-bytes; the CCSDS header has been stripped here
    uint16_t    ccsds_size = 0;         // size (BYTES) of CCSDS header
    // NOTE: the CCSDS header *usually* occupies 6-bytes; it has been stripped here
    uint16_t    packetheader_size = 1;  // size (BYTES) of packet header (e.g. "0xAF" for STEIN)
    uint16_t    timestamp_size = 6;     // size (BYTES) of packet timestamp
    uint16_t    steinframe_size = 495;  // size (BYTES) of STEIN packet data subframe
    uint16_t    housekeep_size = 8;     // size (BYTES) of packet housekeeping subframe
    uint16_t    sparebyte_size = 2;     // size (BYTES) of packet unused bytes
    // NOTE: the observed packet size is actually 514 bytes; the final 2 bytes are spurious
    //
    uint16_t    event_cnt = 198;       // size (# STEIN EVENTS) in one packet of FSW data
   

    // initialize storage arrays
    // STEIN DATA TRANSMISSION SUBFRAME (and extracted quantities) 
    uint32_t    n_events = (line_cnt * event_cnt);     // assumes that we have only STEIN packets
    uint32_t    event_list [line_cnt][event_cnt];      // (for conversion to event-list)
    int16_t      stein_evCode [line_cnt][event_cnt];    // max 2-bits
    int16_t      stein_add [line_cnt][event_cnt];       // max 1-bit
    int16_t      stein_detid [line_cnt][event_cnt];     // max 5-bits
    int16_t     stein_timestamp [line_cnt][event_cnt]; // max 8-bits
    int32_t     stein_eventdata [line_cnt][event_cnt]; // max 16-bits
        // monolithic approach
        //uint32_t    stein_data [6][n_events];
        // *per-packet approach
        //              ...quantity [line_cnt][event_cnt]
        // event-list approach
        //              ...quantity [n_events]
    // 
    // UNEXPLOITED QUANTITIES (extracted and stored, but not presently treated)
    //uint8_t     packet_ccsds [ccsds_size][line_cnt];
    // NOTE: CCSDS data is stripped out in pre-processing, hence this array is NOT FILLED
    uint8_t     packet_header [line_cnt][packetheader_size];
    uint8_t     packet_timestamp [line_cnt][timestamp_size];
    // NOTE: STEIN_FRAME is broken down further
    uint8_t     packet_housekeeping [line_cnt][housekeep_size];
    // NOTE: spare bytes in each frame are disregarded


    // helper variables (storage array indices)
    uint32_t current_packet = 0L;       // tracks packet [line] number
    uint32_t current_event = 0L;        // tracks absolute event number

    // open file for reading
    asciiDataFile.open (fileName, ios::in); 
    if (asciiDataFile.is_open()) {
        cout << "# frame / EVCODE / ADD / DET_ID / TIME_STAMP / DATA\n"; 
        while (asciiDataFile.good()) {
            // 
            // get one line
            getline(asciiDataFile,ascii_line);  
         
            // does line contain data? 
            if (ascii_line.length() > 1) { // yes, proceed to parse
                //
                // instantiate storage array for bytes in one packet
                uint16_t packet_bytes [packet_size];     

                // HEX EXTRACT
                // parse string by delimiter
                vector<string> tokens;                          // instantiate receiver
                Tokenize(ascii_line, tokens, " ");              // parse into elements
                vector<string>::iterator i = tokens.begin();    // instantiate iterator
                //
                // loop over elements: trim and convert from ASCII to BYTE
                for (uint16_t current_byte=0; current_byte < packet_size; current_byte++) {
                    //   
                    // (get length)
                    unsigned int hexbyte_len = (*i).size();
                    
                    // extract the current ascii "hex byte"
                    string ascii_hexbyte = (*i).substr(2, hexbyte_len-3);      
                    
                    // convert to BYTE and store
                    char * cstr = new char [hexbyte_len-3];         // intermediate c_string
                    strcpy (cstr, ascii_hexbyte.c_str());           // convert to c_string
                    char * pEnd;
                    packet_bytes[current_byte] = strtol(cstr,&pEnd,16);
                    
                    // increment vector iterator
                    i++;
                }

                // HEX PARSE
                //
                uint16_t cursor = 0;            // byte-position cursor (for packet) 
                // CCSDS (for usage, define "packet_ccsds" and set "ccsds_size" != 0)
                //for (uint16_t i=0; i < ccsds_size; i++) {
                //    packet_ccsds[current_packet][i] = packet_bytes[cursor];
                //    cursor++;
                //}
                // PACKET HEADER
                for (uint16_t i=0; i < packetheader_size; i++) {
                    packet_header[current_packet][i] = packet_bytes[cursor];
                    cursor++;
                }
                // PACKET TIMESTAMP
                for (uint16_t i=0; i < timestamp_size; i++) {
                    packet_timestamp[current_packet][i] = packet_bytes[cursor];
                    cursor++;
                }
                // ***********
                // STEIN DATA 
                //
                //
                // NOTE: properly, this should be protected with if/else-statements
                // temporary variable (for passing back and forth)
                uint8_t stein_frame [steinframe_size];          // intermediate data storage
                uint32_t event_log [event_cnt];                 // instantiate event_log
                int16_t t_evcode, t_add, t_detid;               // temporary variables
                int16_t t_timestamp;
                int32_t t_eventdata;
                //
                // get STEIN bytes
                for (uint16_t i=0; i < steinframe_size; i++) {
                    stein_frame[i] = packet_bytes[cursor];      // copy out STEIN bytes
                    cursor++;
                }
                // generate an events list from these bytes
                ExtractEvents(stein_frame, event_log);          // extract events
                
                //Parse_EventReport(786688L, t_evcode, t_add, t_detid, t_timestamp, t_eventdata);
                //
                // parse each event into EVCODE, ADD, DETID, TIMESTAMP & EVENTDATA
                for (uint16_t i=0; i < event_cnt; i++) {
                    Parse_EventReport(event_log[i], t_evcode, t_add, t_detid, 
                            t_timestamp, t_eventdata);
                    // copy out to storage arrays 
                    //event_list[current_packet][i]   = current_event; // (causes bus error) 
                    stein_evCode[current_packet][i] = t_evcode; 
                    stein_add[current_packet][i]    = t_add; 
                    stein_detid[current_packet][i]  = t_detid; 
                    stein_timestamp[current_packet][i] = t_timestamp; 
                    stein_eventdata[current_packet][i] = t_eventdata; 
                    
                    cout << current_event << " " << t_evcode << " " << t_add << " " <<
                        t_detid << " " << t_timestamp << " " << t_eventdata << endl;
                    
                    current_event++;
                    cursor += steinframe_size;
                }
                //
                // 
                // ***********
                // HOUSEKEEPING
                for (uint16_t i=0; i < housekeep_size; i++) {
                    packet_housekeeping[current_packet][i] = packet_bytes[cursor];
                    cursor++;
                }
                // SPARE BYTES (UNIMPLEMENTED)
                //
            }
            current_packet++;
            
        }
        asciiDataFile.close();
    } else {
    }
    return 0;
}


