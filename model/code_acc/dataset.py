import numpy as np
import torch
import torch.utils.data as utils

mod_list = ['bpsk', 'qpsk', '8psk', 'dqpsk', 'msk', '16qam', '64qam', '256qam']


def batch_choose():

    train_file = [int(i) for i in range(1, 21)]
    test_file = [int(i) for i in range(21, 29)]

    train_file = np.array(train_file)
    test_file_18 = test_file_22 = np.array(test_file)
    return train_file, test_file_18, test_file_22
 

def create_label(idx):
    input_array = torch.tensor([0, 1, 2, 3, 4, 5, 6, 7])
    n = 500 * len(idx)
    output_array = input_array.repeat(n)
    return output_array.reshape((-1,1))


def load_one_ch(idx, dataset):

    file = []
    for j in idx:
        batch = []
        for i in range(1, 4001):
            with open('../../dataset/CSPB.ML/CSPB_ML_{}_Data/Batch_Dir_{}/signal_{}.tim'.format(dataset, j, (j-1)*4000+i), 'rb') as fid:
                data_array = np.fromfile(fid, np.single)
        
            data_array = data_array[2::2] + 1j * data_array[3::2]
            batch.append(data_array)
        file.append(np.asarray(batch))

    file = np.asarray(file)
    L = file.shape[-1]
    file = file.reshape((-1, L))

    with open(f'../../dataset/CSPB.ML/CSPB_ML_{dataset}_Data/CSPB_ML_{dataset}_Signal_Truth_Labels.txt') as f:
        data = f.readlines()[0::]

    # snr = []
    # for d in data:
    #     snr.append(float(d.split(" ")[-2]))

    # snr = np.array(snr, dtype=np.float16).reshape((28, -1))
    # snr = snr[idx-1, :].flatten()
    # snr = snr.astype(complex)
    # snr = torch.from_numpy(snr).to(torch.complex64).view(-1, 1)
    lrb = []
    for d in data:
        symb = float(d.split(" ")[12]) / float(d.split(" ")[4]) / float(d.split(" ")[10])
        offset = float(d.split(" ")[6])
        l_b = -symb + offset + 0.5
        r_b = symb + offset + 0.5
        lrb.append([l_b, r_b])
    
    lrb = np.array(lrb, dtype=np.float16).reshape((28, 4000, 2))   # 112000, 2
    lrb = lrb[idx-1, :].reshape((-1, 2))
    lrb = torch.from_numpy(lrb).to(torch.complex64)
    file = torch.from_numpy(file).to(torch.complex64)
    data = torch.cat((lrb, file), dim=1)
    
    print ("************ dataset shape is : ", data.shape)

    label = create_label(idx).long()
    data_set = utils.TensorDataset(data, label)
    return data_set
