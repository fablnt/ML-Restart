import time
from datetime import datetime
import sys
import dmtcp
import numpy as np
import gc


a = 0
while True:
    a = a+1

    print(a)
    time.sleep(1)
    if (a == 10):
        dmtcp.checkpoint()
        
