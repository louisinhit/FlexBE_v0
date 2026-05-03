import torch
import torch.nn as nn
import torch.nn.functional as F
import time
# from torch_butterfly import Butterfly  # 假设此模块已正确导入
from functools import partial


Br = 8   # eight branches, which are fixed.



def standardize(input_tensor, dim):
    # Calculate the mean and standard deviation along the chosen dimension
    mean = torch.mean(input_tensor, dim=dim, keepdim=True)
    std = torch.std(input_tensor, dim=dim, keepdim=True)
    
    # Apply Standardization along the chosen dimension
    standardized_tensor = (input_tensor - mean) / (std + 1e-5)
    return standardized_tensor


class BU_Model(nn.Module):
    def __init__(self, N, l, ch, mpexp):
        super().__init__()
        # 保存参数
        self.N = N
        self.l = l
        self.ch = ch
        self.mpexp = mpexp

        # benchmark 模式下不使用 Butterfly
        self.fft = partial(torch.fft.fft, dim=-1)
        # self.lin = nn.Linear(self.l * Br, self.l * Br)
        for idx in range(7):
            setattr(self, f"lin_{idx}", nn.Linear(self.l, self.l))
        
        self.flat = nn.Flatten()

    def forward(self, x):
        # 预计算各分支：形状都是 [B, N]
        B = x.shape[0]
        X0 = x
        X2 = torch.pow(x, 2)
        X6 = torch.pow(x, 3)
        X4 = torch.pow(X2, 2)  # 相当于 x^4

        # 并行计算四个 FFT：将四个分支堆叠成 [4, B, N]
        fft_inputs = torch.stack([X0, X2, X4, X6], dim=0)
        fft_outputs = self.fft(fft_inputs)  # 假设支持 batched FFT along last dimension
        # 拆分结果，形状均为 [B, N]
        X1, X3, X5, X7 = fft_outputs[0], fft_outputs[1], fft_outputs[2], fft_outputs[3]

        # 按照原有顺序构造输出张量，堆叠后形状为 [8, B, N]
        X = torch.stack([X0, X2, X4, X6, X1, X3, X5, X7], dim=0)  #  8, batch size, 32768
        X = torch.abs(X)
        # X = standardize(X, dim=-1)
        
        result = []
        for br in range(Br):
            x = X[br,:,:]
            
            # maxpool expansion layer
            x = x.reshape(B, N//self.ch, self.ch).repeat(1, 1, self.l//self.ch)
            x = self.lin_0(x)
            x = F.relu(x)
            x = x.transpose(1, 2)
            x = F.max_pool1d(x, kernel_size=self.mpexp, stride=self.mpexp).permute(0,2,1) 

            y = self.lin_1(x)
            y = F.relu(y)
            y = self.lin_2(y)
            y = y + x
            y = y.permute(0,2,1)
            x = F.relu(y)
            x = F.max_pool1d(x, kernel_size=8, stride=8).permute(0,2,1)  # B, N, channel * Br
            
            y = self.lin_3(x)
            y = F.relu(y)
            y = self.lin_4(y)
            y = y + x
            y = y.permute(0,2,1)
            x = F.relu(y)
            x = F.max_pool1d(x, kernel_size=8, stride=8).permute(0,2,1)  # B, N, channel * Br

            y = self.lin_5(x)
            y = F.relu(y)
            y = self.lin_6(y)
            y = y + x
            y = y.permute(0,2,1)
            x = F.relu(y)
            x = F.max_pool1d(x, kernel_size=4, stride=4).permute(0,2,1)  # B, N, channel * Br

            result.append(self.flat(x))

        return result



if __name__ == "__main__":
    # 定义相关参数
    N     = 32768
    l     = 32
    mpexp = 4
    ch    = 8
    
    dtype = torch.float32  # 或 torch.complex64，根据需求
    
    test_round = 100
    batch_size = 1   # 新增 batch size 参数

    # 测试 CPU
    device = "cuda:0"
    model = BU_Model(N, l, ch, mpexp).to(device)
    model.eval()
    # 预热 CPU
    with torch.no_grad():
        X = torch.randn(batch_size, N, dtype=torch.complex64, device=device)
        for i in range(5):
            output = model(X)

    timess = []
    with torch.no_grad():
        for i in range(test_round):
            data = torch.randn(batch_size, N, dtype=torch.complex64, device=device) 
            
            start_time = time.time()  # 开始计时
            output = model(data)
            end_time = time.time()  # 结束计时
            timess.append(end_time - start_time)
    
    print("CPU timer list is : ", timess)
    print(f" ***** {device} speed test done... ******")
    print(f"===================  average is : {sum(timess)/len(timess)}")
    

    # 测试 GPU
    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
    model = BU_Model(N, l, ch, mpexp).to(device)
    model.eval()
    # 预热 GPU
    with torch.no_grad():
        X = torch.randn(batch_size, N, dtype=torch.complex64, device=device)
        for i in range(5):
            output = model(X)
    
    timess = []
    with torch.no_grad():
        for i in range(test_round):
            data = torch.randn(batch_size, N, dtype=torch.complex64, device=device)
 
            start_time = time.time()  # 开始计时
            output = model(data)
            end_time = time.time()  # 结束计时
            timess.append(end_time - start_time)

    print("GPU timer list is : ", timess)
    print(f" ***** {device} speed test done... ******")
    print(f"===================  average is : {sum(timess)/len(timess)}")


    # ... (前面的代码保持不变) ...

    # 测试 GPU
    if torch.cuda.is_available():
        device = torch.device("cuda:0")
        model = BU_Model(N, l, ch, mpexp).to(device)
        model.eval()
        
        print(f"Testing on: {torch.cuda.get_device_name(0)}")
        
        # 预热 GPU
        # 增加预热次数，确保 GPU 完全“热身”并进入稳定高性能状态
        print("Warming up GPU...")
        with torch.no_grad():
            # 使用和测试时相同的数据类型和设备
            X = torch.randn(batch_size, N, dtype=torch.complex64, device=device)
            for _ in range(20): # 增加预热次数
                _ = model(X)
        
        # 等待所有预热操作完成
        torch.cuda.synchronize()

        timings = []
        with torch.no_grad():
            for i in range(test_round):
                # 在循环内部创建数据，以模拟真实推理场景
                data = torch.randn(batch_size, N, dtype=torch.complex64, device=device)
                
                # --- 正确的计时方法 ---
                start_event = torch.cuda.Event(enable_timing=True)
                end_event = torch.cuda.Event(enable_timing=True)

                start_event.record() # 记录开始时间点
                
                output = model(data)
                
                end_event.record() # 记录结束时间点
                
                # 等待 GPU 完成所有操作
                torch.cuda.synchronize() 
                
                # 计算事件之间的时间（单位：毫秒）
                elapsed_time_ms = start_event.elapsed_time(end_event)
                timings.append(elapsed_time_ms / 1000.0) # 转换为秒

        # 移除第一个计时，因为它可能包含一些首次执行的开销
        if len(timings) > 1:
            timings = timings[1:]

        print(f"GPU timer list (in seconds): {timings}")
        print(f" ***** {device} speed test done... ******")
        average_time = sum(timings) / len(timings) if timings else 0
        print(f"=================== Average is : {average_time} seconds")
    else:
        print("CUDA is not available.")