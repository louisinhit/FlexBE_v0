import copy
import torch.nn as nn
import torch.nn.functional as F
from attention import Attention

class Transformer(nn.Module):
    def __init__(self, config, idx):
        super().__init__()
        
        self.d = config["transformer_dim"]
        self.dropout_prob = config["dropout_prob"]

        # Determine attention type based on layer index
        threshold_layer = config["fabnet_att_layer"]
        current_layer_inv = config["num_layers"] - (idx + 1)
        
        if (threshold_layer < 0) or (current_layer_inv < threshold_layer):
            self.attn_type = config["attn_type"]
        else:
            self.attn_type = "softmax"

        # Layers
        self.norm1 = nn.LayerNorm(self.d)
        self.norm2 = nn.LayerNorm(self.d)
        self.dropout1 = nn.Dropout(p=self.dropout_prob)

        # Attention setup
        att_config = copy.deepcopy(config)
        att_config["attn_type"] = self.attn_type
        self.mha = Attention(att_config)

        # MLP Block setup
        # Note: Logic for Linear/Sparse_Linear was removed as it resulted in nn.Linear in both cases.
        transformer_dim = config["transformer_dim"]
        hidden_dim = config["transformer_hidden_dim"]
        
        self.mlp_block = nn.Sequential(
            nn.Linear(transformer_dim, hidden_dim),
            nn.GELU(),
            nn.Dropout(p=self.dropout_prob),
            nn.Linear(hidden_dim, transformer_dim),
            nn.Dropout(p=self.dropout_prob)
        )

        # Pooling setup
        if config["pool_type"] == "max":
            self.pool = nn.MaxPool1d(config["pool_stride"], stride=config["pool_stride"])
        else:
            self.pool = nn.AvgPool1d(config["pool_stride"], stride=config["pool_stride"])

    def forward(self, X):
        if self.attn_type == "fft":
            # Logic: Norm -> MHA -> Add -> Norm -> MLP -> Add
            X = self.norm1(self.mha(X)) + X
            X = self.norm2(self.mlp_block(X)) + X

        elif self.attn_type == "mlp":
            # Logic: Norm -> MLP -> Add (Skips attention and second norm block)
            X = self.norm1(self.mlp_block(X)) + X
            
        else:
            # Logic (Standard): Norm -> MHA -> Dropout -> Add -> Norm -> MLP -> Add
            X = self.dropout1(self.mha(self.norm1(X))) + X
            X = self.mlp_block(self.norm2(X)) + X

        # Output processing
        X = F.relu(X)
        X = X.transpose(1, 2)
        X = self.pool(X).transpose(1, 2)
        
        return X


class Model(nn.Module):
    def __init__(self, config, scale):
        super().__init__()

        self.num_layers = config["num_layers"]
        self.tied_weights = config["tied_weights"]
        
        self.expansion = nn.Linear(config["channel"], config["transformer_dim"])
        self.ln = nn.LayerNorm(config["transformer_dim"])

        # Use ModuleList for proper parameter registration and cleaner printing
        self.transformers = nn.ModuleList([
            Transformer(config, idx) for idx in range(self.num_layers)
        ])

        self.linear_0 = nn.Linear(config["transformer_dim"], config["transformer_dim"])
        self.flatten = nn.Flatten()
        self.linear_1 = nn.Linear(scale * config["transformer_dim"], config["num_classes"])

    def forward(self, input_ids):
        X = self.expansion(input_ids)
        X = self.ln(X)
        
        # Initial processing
        X = F.relu(X).transpose(1, 2)
        X = F.max_pool1d(X, 8).transpose(1, 2)

        # Transformer layers
        for layer in self.transformers:
            X = layer(X)

        # Final head
        X = self.linear_0(X)
        X = F.relu(X).transpose(1, 2)
        # Note: Extra pooling steps were commented out in original code
        
        X = self.flatten(X)
        X = self.linear_1(X)
        
        return X