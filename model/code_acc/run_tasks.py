from model_wrapper import BuModel
from dataset import batch_choose, load_one_ch
from torch.utils.data import DataLoader
import torch
import os
import json
import numpy as np
import argparse
import amc_config
import torch.nn.functional as F


parser = argparse.ArgumentParser()
parser.add_argument("--model", type = str, dest = "model", required = True)
parser.add_argument("--task", type = str, help = "task", dest = "task", required = True)
parser.add_argument("--train_set", type = int, default=2018)
parser.add_argument("--cuda", type = int, default=0)

parser.add_argument("--noise_max", type = float, default=0.2)   # 0.1 to 1.0
parser.add_argument("--boi_thre", type = float, default=12.0)

parser.add_argument("--skip_train", type = int, help = "skip_train", dest = "skip_train", default = 0)
parser.add_argument("--is_butterfly", help = "if enable butterfly", dest = "is_butterfly", action='store_true')
parser.add_argument("--fabnet_att_layer", type = int, help = "specify the number of attention layer used in fabnet", dest = "fabnet_att_layer", default = -1)

parser.add_argument("--transformer_dim", type = int, help = "dimision of transformer, 0 keep defualt", default = 0)
parser.add_argument("--transformer_hidden_dim", type = int, help = "hidden dimision of transformer, 0 keep defualt", default = 0)
parser.add_argument("--num_layers", type = int, help = "num of layers, 0 keep defualt", default = 0)

parser.add_argument("--channel", type = int, help = "input channels, 0 keep defualt", default = 0)
parser.add_argument("--pool_stride", type = int, help = "pooling stride, 0 keep defualt", default = 0)
parser.add_argument("--pool_type", type = str, help = "pooling type, max keep defualt", default = "max")
parser.add_argument("--batch_size", type = int, help = "batch_size", default = 0)

parser.add_argument("--is_quant", help = "if apply quantization", dest = "is_quant", action='store_true')
parser.add_argument("--man_bit", type = int, help = "bitwidth of mantissa, 10 as defualt for half precision", default = 10)
parser.add_argument("--exp_bit", type = int, help = "bitwidth of exponent, 5 as defualt for half precision", default = 5)
parser.add_argument("--tile_size", type = int, default = -1)

args = parser.parse_args()

attn_type = args.model
task = args.task

checkpoint_dir = "../logs/"

if not os.path.exists(checkpoint_dir):
    os.makedirs(checkpoint_dir)

print(amc_config.config[task]["extra_attn_config"].keys(), flush = True)

model_config = amc_config.config[task]["model"]
model_config.update(amc_config.config[task]["extra_attn_config"][attn_type])

######################Tuning hyperparameters###################### overwrite the params
if (args.batch_size != 0):             amc_config.config[task]["training"]["batch_size"] = args.batch_size
if (args.transformer_dim != 0):        model_config["transformer_dim"] = args.transformer_dim
if (args.transformer_hidden_dim != 0): model_config["transformer_hidden_dim"] = args.transformer_hidden_dim
if (args.num_layers != 0):             model_config["num_layers"] = args.num_layers
if (args.pool_stride != 0):            model_config["pool_stride"] = args.pool_stride
if (args.pool_type != "max"):          model_config["pool_type"] = args.pool_type
if (args.channel != 0):                model_config["channel"] = args.channel


model_config["mixed_precision"] = True
model_config["attn_type"] = attn_type
model_config["is_butterfly"] = args.is_butterfly
model_config["fabnet_att_layer"] = args.fabnet_att_layer
model_config["is_quant"] = args.is_quant

training_config = amc_config.config[task]["training"]
gpu_memory_config = amc_config.config[task]["gpu_memory"]
print(json.dumps([model_config, training_config], indent = 4))

device_ids = list(range(torch.cuda.device_count()))
print(f"GPU list: {device_ids}")
device = torch.device(f"cuda:{args.cuda}")
# device = torch.device(f"cpu")
model_config["device"] = device


from quant import *
# activation quantization 
model_config["quant_num"] = BlockMinifloat(exp=args.exp_bit, man=args.man_bit, tile=args.tile_size, flush_to_zero=False)

# trainable weights
twi_number = BlockMinifloat(exp=args.exp_bit, man=args.man_bit, tile=0, flush_to_zero=False)
twi_quantizer = quantizer(forward_number=twi_number, backward_number=None, forward_rounding="stochastic")

norm_number = BlockMinifloat(exp=args.exp_bit, man=args.man_bit, tile=0, flush_to_zero=False)
norm_quantizer = quantizer(forward_number=norm_number, backward_number=None, forward_rounding="stochastic")

emb_number = BlockMinifloat(exp=args.exp_bit, man=args.man_bit, tile=-1, flush_to_zero=False)
emb_quantizer = quantizer(forward_number=emb_number, backward_number=None, forward_rounding="stochastic", dimm=0)

mlp_number = BlockMinifloat(exp=args.exp_bit, man=args.man_bit, tile=-1, flush_to_zero=False)
mlp_quantizer = quantizer(forward_number=mlp_number, backward_number=None, forward_rounding="stochastic", dimm=0)


model_config["task"] = task
model_config["train_set"] = args.train_set
model_config["noise_max"] = args.noise_max
model_config["boi_thre"] = args.boi_thre


model = BuModel(model_config)
model.to(device)


log_interval = 100
train_idx, test_idx_2018, test_idx_2022 = batch_choose()

print ("****************", train_idx)
print ("****************", test_idx_2018)
print ("****************", test_idx_2022)


batch_size = amc_config.config[task]["training"]["batch_size"]
layers = str(model_config["num_layers"])
dim = str(model_config["transformer_dim"])
hdim = str(model_config["transformer_hidden_dim"])
ps = str(model_config["pool_stride"])
inch = str(model_config["channel"])
log_f_path = os.path.join(checkpoint_dir, \
            f"{attn_type}_i{inch}_l{layers}_d{dim}_hd{hdim}_p{ps}_{args.train_set}_boi{args.boi_thre}_n{args.noise_max}.log")


with open(log_f_path, 'w') as o:
    o.write("Start \n")

for arg, value in sorted(vars(args).items()):
    with open(log_f_path, 'a') as o:
        o.write(f"Argument {arg} : {value} \n")

def output_s(_message, save_filename):
    print (_message)
    with open(save_filename, 'a') as o:
        o.write(_message + '\n')


print(model)
# output_s(f"parameter_size: {[weight.size() for weight in model.parameters()]}", log_f_path)
output_s(f"num_parameter: {np.sum([np.prod(weight.size()) for weight in model.parameters()])}", log_f_path)

######################################### prepare the train set ########################
print ("*********************** starting loading dataset ******************************* \n")

trainset = load_one_ch(idx=train_idx, dataset=args.train_set)
train_loader = DataLoader(trainset, batch_size=batch_size, shuffle=True, num_workers=2)

testset_2018 = load_one_ch(idx=test_idx_2018, dataset=2018)
test_loader_2018 = DataLoader(testset_2018, batch_size=batch_size, num_workers=2)

testset_2022 = load_one_ch(idx=test_idx_2022, dataset=2022)
test_loader_2022 = DataLoader(testset_2022, batch_size=batch_size, num_workers=2)
print ("*********************** loading dataset done ******************************* \n")


def train(ep):
    train_loss = 0.0
    model.train()

    for batch_idx, (data, target) in enumerate(train_loader):
        data, target = data.to(device), target.to(device)
        optimizer.zero_grad()
        output = model(data)
        target = target.squeeze_()
        loss = criterion(output, target)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.)

        optimizer.step()
        lr_scheduler.step()
        train_loss += loss
        print (train_loss.item())

        # for name,p in model.named_parameters():
        #     k = name.split('.')

        #     if k[-1]=='twiddle':
        #         p.data = twi_quantizer(p.data)

        #     elif k[-2]=='norm2' or k[-2]=='norm1':
        #         p.data = norm_quantizer(p.data)

        #     #elif k[-3]=='embeddings':
        #     #    p.data = emb_quantizer(p.data)

        #     #elif k[-3]=='mlpblock':
        #     #    p.data = mlp_quantizer(p.data)
        if batch_idx > 0 and batch_idx % log_interval == 0:
            my_lr = lr_scheduler.get_last_lr()[0]
            message = ('Train Epoch: {}   \t Loss: {:.6f}\t  lr : {:.6f} '.format(ep, train_loss.item()/log_interval, my_lr))
            output_s(message, log_f_path)
            train_loss = 0.

def test():
    model.eval()
    correct_2018 = 0.
    total_2018 = 0.
 
    with torch.no_grad():
        for data, target in test_loader_2018:
            data, target = data.to(device), target.to(device)
            output = model(data)
            target = target.squeeze_()

            _, predicted = torch.max(output.data, 1)
            total_2018 += target.size(0)
            correct_2018 += (predicted == target).sum().item()
    print ("... Testing on 2018 done ... \n")
    message = ('\nTest set on 2018 : Accuracy: {}/{} ({:.3f}%)\n'.format(correct_2018, total_2018, 100. * correct_2018 / total_2018))
    output_s(message, log_f_path)

    correct_2022 = 0.
    total_2022 = 0.
    
    with torch.no_grad():
        for data, target in test_loader_2022:
            data, target = data.to(device), target.to(device)
            output = model(data)
            target = target.squeeze_()

            _, predicted = torch.max(output.data, 1)
            total_2022 += target.size(0)
            correct_2022 += (predicted == target).sum().item()
    print ("... Testing on 2022 done ... \n")
    message = ('\nTest set on 2022 : Accuracy: {}/{} ({:.3f}%)\n'.format(correct_2022, total_2022, 100. * correct_2022 / total_2022))
    output_s(message, log_f_path)

    return correct_2018 / total_2018, correct_2022 / total_2022



epochs = training_config["num_train_steps"] * batch_size / amc_config.config[task]["dataset"]["train"]
epochs = int(epochs)
output_s(f"number of epoch will be : {epochs}", log_f_path)

optimizer = torch.optim.AdamW(
    model.parameters(),
    lr = 0.003,
    betas = (0.9, 0.999), eps = 1e-6, weight_decay = training_config["weight_decay"]
)


lr_scheduler = torch.optim.lr_scheduler.CyclicLR(
    optimizer = optimizer,
    base_lr = 0.0001,
    max_lr = 0.0007,
    step_size_up = 800,
    mode='triangular',
    cycle_momentum=False
)

criterion = F.cross_entropy

output_s(str(optimizer), log_f_path)
output_s(str(lr_scheduler), log_f_path)

if args.is_quant:
    model.set_quant(True)
    output_s(f"Applying quantization with {args.man_bit}-bit mantissa and {args.exp_bit}-bit exponent", log_f_path)


try:
    checkpoint = torch.load(log_f_path.replace(".log", ".model"))
    model.load_state_dict(checkpoint["model_state_dict"], strict=False)
    output_s(f".............. successful loading {task} task...................", log_f_path)
except:
    with open(log_f_path, 'a') as o:
        o.write(".........None found model!!.....\n")
    print ('...............None found model!!...................')
    pass


if args.skip_train == 0:
    try:
        best_acc_2018 = best_acc_2022 = 0.0
        for epoch in range(1, epochs+1):
            train(epoch)
            test_acc_2018, test_acc_2022 = test()

            if test_acc_2018 > best_acc_2018:
                best_acc_2018 = test_acc_2018
                torch.save({"model_state_dict":model.state_dict()}, log_f_path.replace(".log", ".model"))
                with open(log_f_path, 'a') as out:
                    out.write("########################### Saved 2018 best model. the highest Accuracy on 2018 :{:.5f}".format(best_acc_2018) + '\n')

            if test_acc_2022 > best_acc_2022:
                best_acc_2022 = test_acc_2022
                torch.save({"model_state_dict":model.state_dict()}, log_f_path.replace(".log", ".model"))
                with open(log_f_path, 'a') as out:
                    out.write("########################### Saved 2022 best model. the highest Accuracy on 2022 :{:.5f}".format(best_acc_2022) + '\n')

    except KeyboardInterrupt as e:
        print(e)

# test only
else:
    model.eval()
    test_acc_2018, test_acc_2022 = test()
    print ("...  Testing on 2018 done ... ", "average is : ", test_acc_2018)
    print ("...  Testing on 2022 done ... ", "average is : ", test_acc_2022)


output_s('DONE..', log_f_path)
