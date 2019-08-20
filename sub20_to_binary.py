#!/usr/bin/env python
#
# sub20_to_binary.py - Python code to pack SUB-20 output as binary event data
#    (to make use of STEIN data collected via the SUB20 interface)
#
# 
# Usage:
#  log.log - data collected via SUB-20
#  binary.log - binary-packed event data, created from "log.log" via the python script "sub20_to_binary.py"
#  binary.txt - unpacked event data, created from ..binary.log
#     via the usual C++ rawstein_extract code
# 
# >>> import sub20_to_binary as sub20
# >>> bin = sub20.read_sub20_hexbytes("log.log")
# >>> sub20.write_sub20_hexbytes(data=bin, filename="binary.log")
#
# Author:
#  Karl Yando
#
#########################################
# Copyright 2013 Karl Yando
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#########################################


import array
import csv
import ctypes
import binascii

PyLong_AsByteArray = ctypes.pythonapi._PyLong_AsByteArray
PyLong_AsByteArray.argtypes =  [ctypes.py_object,
                                ctypes.c_char_p,
                                ctypes.c_size_t,
                                ctypes.c_int,
                                ctypes.c_int]
def packl_ctypes(lnum):
    a = ctypes.create_string_buffer(lnum.bit_length()//8 + 1)
    PyLong_AsByteArray(lnum, a, len(a), 0, 1)
    return a.raw

def packl(lnum, padmultiple=1):
    """Packs the lnum (which must be convertable to a long) into a
       byte string 0 padded to a multiple of padmultiple bytes in size. 0
       means no padding whatsoever, so that packing 0 result in an empty
       string.  The resulting byte string is the big-endian two's
       complement representation of the passed in long."""

    if lnum == 0:
        return b'\0' * padmultiple
    elif lnum < 0:
        raise ValueError("Can only convert non-negative numbers.")
    s = hex(lnum)[2:]
    s = s.rstrip('L')
    if len(s) & 1:
        s = '0' + s
    s = binascii.unhexlify(s)
    if (padmultiple != 1) and (padmultiple != 0):
        filled_so_far = len(s) % padmultiple
        if filled_so_far != 0:
            s = b'\0' * (padmultiple - filled_so_far) + s
    return s

# procedure to read in ASCII text dumps of full-resolution (32-bit)
#  STEIN data, collected via the SUB-20 interface
def read_sub20_hexbytes(filename=None, dialect="whitespace"):
    
    # do we have a valid filename?
    try:
        f = open(filename, 'rU')
    except IOError as errno:
        print("read_sub20_hexbytes: Invalid filename or path")
        print("I/O error({0}):".format(errno))
    else:
        # use the CSV reader to simplify the process
        reader = csv.reader(f,dialect=dialect)
       
        lines = []
        # examine and parse each record
        for row in reader:
            # SUB20-generated logs consist of 4 hexbytes printed with 
            #   ASCII characters, followed by an ASCII gloss
            # e.g.
            #   80 00 00 00                                     | ....
            #   40 00 00 00                                     | @...
            hexbyte_list = []
            if len(row) > 0:    # actual data; begin parsing
                for hexbyte in row[0:4]:
                    # convert ASCII hexbytes to real hexbytes
                    hexbyte_list.append(int(hexbyte,16))
                # pack the event in binary format
                binary = (hexbyte_list[0] << 24) + (hexbyte_list[1] << 16) + (hexbyte_list[2] << 8) + (hexbyte_list[3] << 0)
                lines.append(binary)
            # else: an empty row; do nothing
    finally:
        f.close()
    return lines

def write_sub20_hexbytes(data, filename=None):

    try:
        f = open(filename, 'wb')
    except IOError as errno:
        print("write_sub20_hexbytes: Invalid filename or path")
        print("I/O error({0}):".format(errno))
    else:
        for i in data:
            f.write(packl(i, padmultiple=4))
    finally:
        f.close()

csv.register_dialect("whitespace", delimiter=' ', skipinitialspace=True) 
