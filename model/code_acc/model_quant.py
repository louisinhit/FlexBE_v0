
import torch
import torch.nn as nn
from attention_quant import Attention_Quant
#from qtorch.quant import Quantizer
from quant import *
import copy


class EmbedNorm(nn.Module):
    def __init__(self, config, eps=1e-6):
        super().__init__()
        self.a_2 = nn.Parameter(torch.ones(config["transformer_dim"]))
        self.b_2 = nn.Parameter(torch.zeros(config["transformer_dim"]))
        self.eps = eps

    def forward(self, x):
        mean = x.mean(-1, keepdim=True)
        std = x.std(-1, keepdim=True)
        return self.a_2 * (x - mean) / (std + self.eps) + self.b_2


class Transformer(nn.Module):
    def __init__(self, config, idx):
        super().__init__()

        self.is_quant = False

        if ((config["fabnet_att_layer"]<0) or ((config["num_layers"]-(idx+1)) < config["fabnet_att_layer"])):
            self.attn_type = config["attn_type"]
        else:
            self.attn_type = "softmax"

        self.norm1 = nn.LayerNorm(config["transformer_dim"])
        att_config = copy.deepcopy(config)
        att_config["attn_type"] = self.attn_type
        self.mha = Attention_Quant(att_config)

        self.dropout1 = torch.nn.Dropout(p = config["dropout_prob"])
        self.norm2 = nn.LayerNorm(config["transformer_dim"])
        
        if config["is_butterfly"] and self.attn_type != "softmax":
            # Linear = Sparse_Linear
            self.linear1 = Sparse_Linear(config["transformer_dim"], config["transformer_hidden_dim"], increasing_stride=False)
            self.linear2 = Sparse_Linear(config["transformer_hidden_dim"], config["transformer_dim"], increasing_stride=False)
        else:
            # Linear = nn.Linear
            self.linear1 = nn.Linear(config["transformer_dim"], config["transformer_hidden_dim"], dtype=torch.float32)
            self.linear2 = nn.Linear(config["transformer_hidden_dim"], config["transformer_dim"], dtype=torch.float32)

        self.mha_quantizers = []
        for i in range(2):
            (self.mha_quantizers).append(Quantizer(forward_number=config["quant_num"], backward_number=None, forward_rounding="stochastic"))

        self.mlp_quantizers = []
        for i in range(5):
            (self.mlp_quantizers).append(Quantizer(forward_number=config["quant_num"], backward_number=None, forward_rounding="stochastic"))
        # self.linear1 = Linear(config["transformer_dim"], config["transformer_hidden_dim"]) 
        self.gelu = nn.GELU()
        self.mlp_dropout1 = torch.nn.Dropout(p = config["dropout_prob"])
        # self.linear2 = Linear(config["transformer_hidden_dim"], config["transformer_dim"])
        self.mlp_dropout2 = torch.nn.Dropout(p = config["dropout_prob"])
        
        self.task = config["task"]

        #######################
        self.pool = nn.MaxPool1d(config["max_pool"], stride=config["max_pool"])

    def set_quant(self, is_quant):
        self.is_quant = is_quant
        self.mha.is_quant = is_quant

    def forward(self, X):
        if self.attn_type == "fft":
            Y = self.norm1(X)
            if self.is_quant: Y = (self.mha_quantizers[0])(Y)
            Y = self.mha(Y)
            X = Y + X
            if self.is_quant: X = (self.mha_quantizers[1])(X)

        else:
            Y = self.norm1(X)
            if self.is_quant: Y = (self.mha_quantizers[0])(Y)
            Y = self.mha(Y)
            Y = self.dropout1(Y)
            X = Y + X
            if self.is_quant: X = (self.mha_quantizers[1])(X)

        # Perform Norm with quant
        Y = self.norm2(X)
        if self.is_quant:
            Y = (self.mlp_quantizers[0])(Y)

        Y = self.linear1(Y)
        if self.is_quant: Y = (self.mlp_quantizers[1])(Y.float())
        
        Y = self.gelu(Y)
        if self.is_quant: Y = (self.mlp_quantizers[2])(Y)
        Y = self.mlp_dropout1(Y)
        Y = self.linear2(Y)
        if self.is_quant: Y = (self.mlp_quantizers[3])(Y.float())
 
        Y = self.mlp_dropout2(Y)
        X = Y + X
        if self.is_quant: X = (self.mlp_quantizers[4])(X)
        # pooling layer to shorten the size
        X = X.permute(0, 2, 1)
        X = self.pool(X).permute(0, 2, 1)

        return X


class Model_Quant(nn.Module):
    def __init__(self, config):
        super().__init__()

        self.num_layers = config["num_layers"]
        self.tied_weights = config["tied_weights"]
        ###### Quantization ######
        self.is_quant = False
        self.emd_quantizer = Quantizer(forward_number=config["quant_num"], backward_number=None, forward_rounding="stochastic")
        self.last_quantizer = Quantizer(forward_number=config["quant_num"], backward_number=None, forward_rounding="stochastic")
        #self.embeddings = EmbedNorm(config)
        self.expansion = nn.Linear(config["channel"], config["transformer_dim"])

        if self.tied_weights:
            self.transformer = Transformer(config)
        else:
            for idx in range(self.num_layers):
                setattr(self, f"transformer_{idx}", Transformer(config, idx))

        self.norm = nn.LayerNorm(config["transformer_dim"])

    def set_quant(self, is_quant):
        self.is_quant = is_quant
        for idx in range(self.num_layers):
            getattr(self, f"transformer_{idx}").is_quant = is_quant


    def forward(self, input_ids):

        #X = self.embeddings(input_ids)
        X = self.expansion(input_ids)

        if self.is_quant:
            X = self.emd_quantizer(X)

        if self.tied_weights:
            for idx in range(self.num_layers):
                X = self.transformer(X)
        else:
            for idx in range(self.num_layers):
                X = getattr(self, f"transformer_{idx}")(X)

        X = self.norm(X)

        if self.is_quant: 
            X = self.last_quantizer(X)

        return X
