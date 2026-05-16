import torch
import time
import torch.nn as nn
from model import Model
from model_quant import Model_Quant
import torch.nn.functional as F

Br = 8

def standardize(input_tensor, dim):
    # Calculate the mean and standard deviation along the chosen dimension
    mean = torch.mean(input_tensor, dim=dim, keepdim=True)
    std = torch.std(input_tensor, dim=dim, keepdim=True)
    # Apply Standardization along the chosen dimension
    standardized_tensor = (input_tensor - mean) / (std + 1e-5)
    return standardized_tensor

class FeatureExtract(nn.Module):
    """
    Feature Extraction Module.
    
    This module performs signal pre-processing, including Band-of-Interest (BOI) 
    detection and centering.
    
    The BOI algorithm implemented here is based on the work by C. M. Spooner regarding 
    white-space detection and signal isolation.
    
    Reference:
    ----------
    Title: Multi-resolution white-space detection for cognitive radio
    Author: C. M. Spooner
    Conference: Proc. IEEE Mil. Commun. Conf. (MILCOM), Orlando, FL, USA, 2007, pp. 1–9.
    Link:
    https://ieeexplore.ieee.org/document/4455182
    """
    def __init__(self, config):
        super().__init__()
        
        self.min_value = 0.
        self.max_value = config["noise_max"]  # 0.1  控制加噪大小
        self.boi_thre = config["boi_thre"]  # 12.0 - 20.0
        
    def _stand_randn(self, data):
        lrb, data = torch.split(data, [2, 32768], dim=1)

        if self.training:
            random_float = self.min_value + torch.rand(1) * (self.max_value - self.min_value)
            noise = torch.randn_like(data) * random_float.to(data.device)
            data = data + noise
        return lrb.real, data

    def _roll_along(self, arr, shifts, dim=1):
        assert arr.ndim - 1 == shifts.ndim
        dim %= arr.ndim
        shape = (1,) * dim + (-1,) + (1,) * (arr.ndim - dim - 1)
        dim_indices = torch.arange(arr.shape[dim]).reshape(shape).to(arr.device)
        indices = (dim_indices - shifts.unsqueeze(dim)) % arr.shape[dim]
        return torch.gather(arr, dim, indices)

    def _boi(self, input_tensor, lrb, thre=14., window=15):
        """
        Band of Interest (BOI) detection logic.
        See: C. M. Spooner, "Multi-resolution white-space detection for cognitive radio," MILCOM 2007.
        """
        L, C = input_tensor.size(-1), input_tensor.size(-1) // 2

        X_fft = torch.fft.fft(input_tensor, dim=-1)
        X_fft = torch.fft.fftshift(X_fft, dim=-1)
        X_psd = torch.abs(X_fft)**2

        max_value = torch.max(X_psd, dim=-1).values
        threshold = max_value / thre
        # BOI detect and thresholding
        clipped_psd = torch.where(X_psd < threshold.unsqueeze(dim=-1), torch.tensor(0.0).to(input_tensor.device), X_psd)
        # Set elements outside the range [10:80] in the last dimension to zero
        
        w = (window-1)//2
        # smoothing the spectrum
        Xs = F.pad(clipped_psd, (w, window-1-w), "constant", 0.)
        Xs = F.conv1d(Xs.unsqueeze(1), torch.ones(1, 1, window).to(Xs.device)/window).squeeze()
        Xr = torch.sqrt(Xs) * torch.exp(1j * torch.angle(X_fft))

        center = L * (lrb[:,0] + lrb[:,1]) / 2.
        center = center.to(torch.int)
        Xr = self._roll_along(Xr, C - center, -1)
        return torch.fft.ifft(torch.fft.ifftshift(Xr, dim=-1), dim=-1)

    def forward(self, X):
        lrb, X = self._stand_randn(X)
        X = self._boi(X, lrb)

        a = X.real
        b = X.imag
        X = X / torch.sqrt(torch.mean(a**2 + b**2, dim=-1, keepdim=True))
        return X

def preprocess_fft(X):
    """
    Constructs custom feature extraction layers (Higher-order statistics/powers).
    
    This implementation generates multiple branches of signal features (powers and their FFTs),
    derived from the architecture described in the following paper:
    
    Reference:
    ----------
    Title: Deep-Learning-Based Classifier With Custom Feature-Extraction Layers for Digitally Modulated Signals
    Link: https://ieeexplore.ieee.org/document/9652033 (or similar DOI based on publication venue)
    """

    #X_fft = torch.fft.fftshift(torch.fft.fft(X, norm="ortho"), dim=-1)

    # branch 0
    X0 = torch.pow(X, 2)

    # branch 1
    X1 = torch.fft.fftshift(torch.fft.fft(X0, norm="ortho"), dim=-1)
    
    # branch 2
    X2 = torch.pow(X0, 2) # Equivalent to X^4
    
    # branch 3
    X3 = torch.fft.fftshift(torch.fft.fft(X2, norm="ortho"), dim=-1)

    # branch 4
    X4 = torch.pow(X2, 2) # Equivalent to X^8
    
    # branch 5
    X5 = torch.fft.fftshift(torch.fft.fft(X4, norm="ortho"), dim=-1)

    # branch 6
    X6 = torch.pow(X0, 3) # Equivalent to X^6
    
    # branch 7
    X7 = torch.fft.fftshift(torch.fft.fft(X6, norm="ortho"), dim=-1)

    #Y = torch.stack([X, X_fft, X0, X1, X2, X3, X4, X5, X6, X7])
    Y = torch.stack([X0, X1, X2, X3, X4, X5, X6, X7])
    return torch.abs(Y)

class BuModel(nn.Module):

    def __init__(self, config):
        super().__init__()
        self.preprocess = FeatureExtract(config)
        self.channel = config["channel"]
        self.pooling_mode = config["pooling_mode"]
        self.trans_dim = config["transformer_dim"]

        scale = config["data_length"] / config["channel"]
        scale = scale / (config["pool_stride"]** config["num_layers"])
        scale = int(scale) // 8
        if scale < 1.:
            raise ValueError("*** WRONG LENGTH OF DATA!!! ***")

        self.branch_0 = Model(config, scale=scale)
        self.branch_1 = Model(config, scale=scale)
        self.branch_2 = Model(config, scale=scale)
        self.branch_3 = Model(config, scale=scale)
        self.branch_4 = Model(config, scale=scale)
        self.branch_5 = Model(config, scale=scale)
        self.branch_6 = Model(config, scale=scale)
        self.branch_7 = Model(config, scale=scale)
        
        self.flatten = nn.Flatten()
        self.seq_classifer = nn.Linear(Br * config["num_classes"], config["num_classes"])

    def set_quant(self, is_quant):
        self.branch_0.set_quant(is_quant)
        self.branch_1.set_quant(is_quant)
        self.branch_2.set_quant(is_quant)
        self.branch_3.set_quant(is_quant)
        self.branch_4.set_quant(is_quant)
        self.branch_5.set_quant(is_quant)
        self.branch_6.set_quant(is_quant)
        self.branch_7.set_quant(is_quant)

    def forward(self, X):
        # Feature extraction (Paper 1: Spooner, MILCOM 2007)
        X = self.preprocess(X)

        # FPGA starts here...
        # Custom Feature Extraction Layers (Paper 2: Deep-Learning-Based Classifier...)
        X = preprocess_fft(X)
        
        bs = X.shape[1]
        X = standardize(X, dim=-1)
        X = X.reshape((Br, bs, -1, self.channel))

        out_0 = self.branch_0(X[0,:,:,:])
        out_1 = self.branch_1(X[1,:,:,:])
        out_2 = self.branch_2(X[2,:,:,:])
        out_3 = self.branch_3(X[3,:,:,:])
        out_4 = self.branch_4(X[4,:,:,:])
        out_5 = self.branch_5(X[5,:,:,:])
        out_6 = self.branch_6(X[6,:,:,:])
        out_7 = self.branch_7(X[7,:,:,:])
        
        #out = torch.cat((out_0, out_1, out_2, out_3, out_4, out_5, out_6, out_7, out_8, out_9), dim=-1)
        out = torch.cat((out_0, out_1, out_2, out_3, out_4, out_5, out_6, out_7), dim=-1)

        out = self.flatten(out)
        out = self.seq_classifer(out)
        return F.log_softmax(out, dim=1)
