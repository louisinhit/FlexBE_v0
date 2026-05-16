import argparse
import time
import torch
import torch.nn.functional as F
from quant import *


torch.manual_seed(23)


# add some examples to test saturation limits
data = torch.tensor([0
    ,0.125
    ,0.25
    ,0.375
    ,0.5
    ,0.75
    ,1.0
    ,1.5 ])

sign = torch.sign(data) 
#data = (data**2)*sign

num = BlockMinifloat(exp=2, man=1, tile=-1)
quant_func = quantizer(forward_number=num, forward_rounding="stochastic")

qdata = quant_func(data)


print("Input:", data, "\n-----------------------------")
print("Quant:", qdata, "\n-----------------------------")
print("--------------------------------------")
print("Error:", data-qdata, torch.sum((data-qdata)**2)/(len(data)))

