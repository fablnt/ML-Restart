import time
from datetime import datetime
import sys
import dmtcp
import torch
import numpy as np
import gc

# Stampa tutti gli argomenti

a=0
while True:
    a += 1
    print(a)
    time.sleep(1)
    if a == 10:
        dmtcp.checkpoint()
