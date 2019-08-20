//
// rawstein_extract.cpp -- C++ code to produce an ASCII event list from
// the raw binary bytes produced by STEIN.  Compiles with g++.  If compiled 
// binary has name "raw_steinunpack", then usage on a UNIX machine is:
//
//    ./raw_steinunpack STEIN_RAWBYTESLOG.log > STEINBYTESLOG.txt
//
// where "STEIN_RAWBYTESLOG.log" is the name and path of the packed
//  binary file, and "STEINBYTESLOG.txt" is the name and path of the
//  output file, to which an ASCII event list will be written.
//
// (see usage notes in sub20_to_binary.py, if conversion from raw dump 
//   to packed binary is needed)
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
using namespace std;

// from <http://c-faq.com/misc/hexio.html>
char *baseconv(unsigned int num, int base) {
    static char retbuf[33];
    char *p;

    if(base < 2 || base > 16)
        return NULL;

    p = &retbuf[sizeof(retbuf)-1];
    *p = '\0';

    do {
        *--p = "0123456789abcdef"[num % base];
        num /= base;
    } while(num != 0);

    return p;
}


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
    uint32_t binary_len = 0;

    // attempt to get file size, in bytes
    if (stat(fileName, &results) == 0) {
        // success; copy result to variable "binary_len"
        binary_len = results.st_size;
    } else {
        // file open FAILED
        cout << "Invalid file name / path: read failed!\n";
        return 0;
    }

    // initialize storage array
    char * binary_data;
    binary_data = new char [binary_len];
    
    // open file for reading
    ifstream binaryDataFile (fileName, ios::in | ios::binary);
    // begin reading
    binaryDataFile.read(binary_data,binary_len);
    
    if (!binaryDataFile) {
        // error has occured in reading
        cout << "error during read! \n";
        delete[] binary_data;   // relinquish claimed memory
        binaryDataFile.close(); // close file
        return 0;
    } else {
        cout << "# Import successful; bytes read: ";
        cout << binaryDataFile.gcount() << "\n";
        binaryDataFile.close(); // close file
    }
    

    // 32-bit data packets, so each packet is actually spread across four CHAR bytes (8 hex characters)
    
    // conversion from signed to unsigned bytes
    unsigned char * raw;
    raw = new unsigned char [binary_len];
    for (uint32_t i=0L; i<binary_len; i++) {
       raw[i] = (unsigned char)(binary_data[i]);
    } 
    // operation complete
    
    // we've now copied over the contents of "binary_data",
    //   so we can relinquish that memory 
    delete[] binary_data;
   
    // with very large datafiles, if we attempt to hold variable arrays
    //   in memory, then we appear to *run out* of allocatable memory,
    //   and begin to incur memory errors and seg faults
    // to avoid this situation, we can print out the variable values
    //   as they are processed, which should hugely reduce memory usage
    unsigned long n_frames = binary_len/4L;
    unsigned char evcode;
    unsigned char add;
    unsigned char det_id;
    unsigned char timestamp;
    unsigned short data;  
        // NOTE: STEIN data is properly interpreted as a *signed* 16-bit int

    // *not necessary* to open a specific file, as we use standard out
    // write ourselves a header
    cout << "# frame / EVCODE / ADD / DET_ID / TIME_STAMP / DATA\n"; 

    // primary loop
    for (uint32_t i=0L; i < n_frames; i++) {
        // EVCODE(1:0) [1st CHAR]
        evcode = (raw[4L*i] >> 6) & 0xff  ; 
        // ADD(0) [1st CHAR]
        add = (raw[4L*i] >> 5) - (evcode << 1); 
        // DET ID(4:0) [1st CHAR]
        det_id = raw[4L*i]  - ((raw[4L*i] >> 5) << 5); 
        // TIME STAMP(7:0) [2nd CHAR]
        timestamp = raw[4L*i+1L];
        // DATA(15:0) [3rd + 4th CHARs]
        data = (raw[4L*i + 2L] << 8) + (raw[4L*i + 3L]);

        // manual "shift", to take us from a (misinterpreted) 
        //   signed value to a *true* unsigned value
        data = (data + 32768);  // (type is UINT16, so rolls over at 2L^16)

        // write out results 
        cout << i << " ";
        cout << baseconv(evcode,10) << " ";
        cout << baseconv(add,10) << " "; 
        cout << baseconv(det_id,10) << " ";
        cout << baseconv(timestamp,10) << " "; 
        cout << baseconv(data, 10) << endl;
    }
    
    // input file already closed - nothing to do
    // manually free up allocated memory (necessary?)
    delete[] raw;
    
    // done
    return 0;
}


