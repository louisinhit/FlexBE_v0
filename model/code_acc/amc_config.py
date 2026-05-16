config = {
    "modulation":{
        "dataset":{
            "train" :80000,
            "test"  :32000,
        },
        "model":{
            "data_length":32768,
            "learn_pos_emb":True,
            "tied_weights":False,
            "channel":8,    ###
            "transformer_dim":64, ###
            "transformer_hidden_dim":64, ###
            "head_dim":1,
            "num_head":1,
            "num_layers":3, ###
            "pool_stride":8, ###
            "pool_type":"max",
            "dropout_prob":0.01,
            "attention_dropout":0.01,
            "pooling_mode":"LAST", ###
            "num_classes":8,
        },
        "training":{
            "batch_size":160,
            "learning_rate":0.005,
            "warmup":175,
            "lr_decay":"linear",
            "weight_decay":0,
            "num_train_steps":80000,
        },
        "gpu_memory":{
            "softmax":32,
            "fft":32,
            "mlp":32,
            "nystrom-32":32,
            "nystrom-64":32,
            "nystrom-128":32,
            "nystrom-256":32,
            "linformer-256":32,
            "reformer-2":32,
            "performer-256":32,
            "linear":32,
        },
        "extra_attn_config":{
            "softmax":{"attention_grad_checkpointing":True},
            "fft":{"attention_grad_checkpointing":False},
            "mlp":{"attention_grad_checkpointing":False},
            "nystrom-32":{"attention_grad_checkpointing":False, "num_landmarks":32, "conv_kernel_size":35},
            "nystrom-64":{"attention_grad_checkpointing":False, "num_landmarks":64, "conv_kernel_size":35},
            "nystrom-128":{"attention_grad_checkpointing":False, "num_landmarks":128, "conv_kernel_size":35},
            "nystrom-256":{"attention_grad_checkpointing":False, "num_landmarks":256, "conv_kernel_size":35},
            "linformer-256":{"attention_grad_checkpointing":False, "linformer_k":256},
            "reformer-2":{"attention_grad_checkpointing":False, "num_hash":2},
            "performer-256":{"attention_grad_checkpointing":False, "rp_dim":256, "kernel_type":"relu"},
            "linear":{"attention_grad_checkpointing":False},
        }
    }
}
