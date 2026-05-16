import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.autograd import Variable
import numpy as np
import math

# block design implementations
# block_type = "w" weight, "x" activation


# calc_padding
def calc_padding(fold, dim):
    if fold>=dim:
        nstack = 1
    else:
        quo,rem = divmod(dim, fold)
        nstack = quo+(rem>0)
    num = nstack*fold
    p = num-dim
    return int(p)

# block entire vector
def block_V(data, ebit, func):

    #print ('here block V \n')

    entry = func(torch.abs(data), 0) #.item()
    if entry == 0: return data
    shift_exponent = torch.floor(torch.log2(entry+1e-28))
    shift_exponent = torch.clamp(shift_exponent, -2**(ebit-1), 2**(ebit-1)-1)
    return shift_exponent
    #entry = func(torch.abs(data), 0).item()
    #if entry == 0: return data
    #shift_exponent = math.floor(math.log2(entry))
    #shift_exponent = min(max(shift_exponent, -2**(ebit-1)), 2**(ebit-1)-1)
    #return shift_exponent


# block on axis=0
def block_B(data, ebit, func):

    #print ('here block B \n')

    entry = func(torch.abs(data.view(data.size(0), -1)), 1)#[0] 
    shift_exponent = torch.floor(torch.log2(entry+1e-28))
    shift_exponent = torch.clamp(shift_exponent, -2**(ebit-1), 2**(ebit-1)-1)
    shift_exponent = shift_exponent.view([data.size(0)]+[1 for _ in range(data.dim()-1)])
    return shift_exponent

# block entire tensor
def block_B0(data, ebit, func):
    
    #print ('here block B0 \n')

    entry = func(torch.abs(data.view(-1)), 0).item()
    if entry == 0: return data
    shift_exponent = math.floor(math.log2(entry))
    shift_exponent = min(max(shift_exponent, -2**(ebit-1)), 2**(ebit-1)-1)
    return shift_exponent


#"""
# block by some factor on axis=0,1 (dim=2)
def block_BG2(data, factors, ebit, func):
    
    #print ('here block BG2 \n')

    dim = data.size()
    assert len(dim) == 2

    # factors already 2D
    fact = [factors[i] if factors[i] != -1 else dim[i] for i in range(2)]

    # pad each dimension
    num_pad = [calc_padding(fact[i], dim[i]) for i in range(2)]
    padding =tuple([0,num_pad[1],0,num_pad[0]])
    data = F.pad(input=data, pad=padding, mode='constant', value=0)
    dim_pad = data.size()

    # unfold
    data_unf = data.unfold(0, fact[0], fact[0]).unfold(1, fact[1], fact[1])

    # calc shift_exponent for block
    data_f = data_unf.contiguous().view([data_unf.size(0), data_unf.size(1),-1])
    tiles = data_f.size()[:2]
    mean_entry = func(torch.abs(data_f), 2) #[0]
    shift_exponent = torch.floor(torch.log2(mean_entry+1e-28))
    shift_exponent = torch.clamp(shift_exponent, -2**(ebit-1), 2**(ebit-1)-1)

    # reverse the unfold
    shift_exponent = shift_exponent.repeat(fact[0],fact[1])
    shift_exponent = shift_exponent.view(fact[0],tiles[0],fact[1],tiles[1])
    shift_exponent = shift_exponent.transpose(0,1).transpose(2,3)
    shift_exponent = shift_exponent.contiguous().view([dim_pad[0],dim_pad[1]])

    # remove the padding
    shift_exponent = shift_exponent[:dim[0],:dim[1]]

    return shift_exponent


# block by some factor on axis=0,1,2 (data_dim=4)
def block_BG4(data, factors, ebit, func):

    #print ('here block BG4 \n')

    _dim = data.size()
    assert len(_dim) == 4 
    
    # always fold last two dims (in BCHW order)
    data = data.view([_dim[0], _dim[1], -1])
    dim = data.size()
    fact = [factors[i] if factors[i] != -1 else dim[i] for i in range(3)]

    # pad each dimension
    num_pad = [calc_padding(fact[i], dim[i]) for i in range(3)]
    padding =tuple([0,num_pad[2],0,num_pad[1],0,num_pad[0]])
    data = F.pad(input=data, pad=padding, mode='constant', value=0)
    dim_pad = data.size()

    # unfold
    data_unf = data.unfold(0, fact[0], fact[0]).unfold(1, fact[1], fact[1]).unfold(2, fact[2], fact[2])

    # calc shift_exponent for block
    data_f = data_unf.contiguous().view([data_unf.size(0), data_unf.size(1), data_unf.size(2),-1])
    tiles = data_f.size()[:3]
    mean_entry = func(torch.abs(data_f), 3)#[0]
    shift_exponent = torch.floor(torch.log2(mean_entry+1e-28))
    shift_exponent = torch.clamp(shift_exponent, -2**(ebit-1), 2**(ebit-1)-1)

    # reverse the unfold
    shift_exponent = shift_exponent.repeat(fact[0],fact[1],fact[2])
    shift_exponent = shift_exponent.view(fact[0],tiles[0],fact[1],tiles[1],fact[2],tiles[2])
    shift_exponent = shift_exponent.transpose(0,1).transpose(2,3).transpose(4,5)
    shift_exponent = shift_exponent.contiguous().view([dim_pad[0],dim_pad[1],dim_pad[2]])

    # remove the padding
    shift_exponent = shift_exponent[:dim[0],:dim[1],:dim[2]]

    # resize to dim=4 tensor
    shift_exponent = shift_exponent.view(_dim)

    return shift_exponent


def block_BFP(data, ebit, tensor_type, block_factor, func):

    #print ('here block bfp \n')

    data_dim = data.dim()

    dims = data.shape

    # tile
    if block_factor == 1:
        f0,f1 = 1,dims[-1]
    else:
        f0,f1 = int(block_factor),int(block_factor)

    # default (-1 means the whole dimension shares one exponent)
    p0,p1,p2 = 1,1,-1 # same as BC
    
    # decode
    if tensor_type == "x":
        if data_dim == 2:
            p0,p1 = f1,f0

        elif data_dim == 3:
            p0,p1,p2 = f0,f1,1
       
        elif data_dim == 4:
            p0,p1,p2 = 1,f0,f1
            
    elif tensor_type == "w":
        if data_dim == 2:
            p0,p1 = f1,f0
        elif data_dim == 4:
            p0,p1,p2 = f1,f0,-1
    else:
        raise ValueError("Invalid tensor_type option {}".format(tensor_type))

    if data_dim == 2:
        if data.size()[1]<block_factor:
            shift_exponent = block_B(data, ebit, func)
        else:
            shift_exponent = block_BG2(data, [p0,p1], ebit, func)
    
    # 3D tensor only support activation type
    elif data_dim == 3 and tensor_type == 'x':

        data = data.permute((1,2,0))
        data = data.unsqueeze(-1)
        shift_exponent = block_BG4(data, [p0,p1,p2], ebit, func)
        shift_exponent = shift_exponent.squeeze().permute((2,0,1))
        #print (shift_exponent)

    elif data_dim == 4:
        #if data.size()[1]<block_factor:
        #    shift_exponent = block_B(data, ebit, func)
        #else:
        
        shift_exponent = block_BG4(data, [p0,p1,p2], ebit, func) 
    else:
        raise ValueError("Invalid data_dim option {}".format(data_dim)) 
    
    return shift_exponent

#"""

def block_design(data, tile, tensor_type, func, dim=None):

    dim_threshold = 1
    ebit = 8

    if tile == -1:
        if dim is None:
            assert data.dim() <= 4
            if data.dim() <= dim_threshold:
                shift_exponent = block_V(data, ebit, func)
            else:
                shift_exponent = block_B(data, ebit, func)
        else:
            dimlist = [i for i in range(data.dim())]
            dimlist.pop(dim)
            dimlist.insert(0,dim)
            #print (dimlist)
            
            data = data.permute(dimlist).contiguous()
            shift_exponent = block_B(data, ebit, func)

            dimlist = [i for i in range(data.dim())]
            dimlist.pop(0)
            dimlist.insert(dim,0)
            #print (dimlist)
            shift_exponent = shift_exponent.permute(dimlist).contiguous()


    # not good ..
    elif tile == 0:
        shift_exponent = block_B0(data, ebit, func)

    else:
        assert data.dim() <= 4
        if data.dim() <= dim_threshold:
            shift_exponent = block_V(data, ebit, func)
        else:
            shift_exponent = block_BFP(data, ebit, tensor_type, tile, func)

    return shift_exponent


if __name__ == '__main__':
    max_func = lambda x, dim: torch.max(x, dim)[0]
    ebit = 8

    a = torch.randn(2, 1, 8, 128, 2, 2)/5.
    sh = block_design(a, tile=-1, tensor_type='x', func=max_func, dim=2)

    print (sh)
    print (sh.shape)
    