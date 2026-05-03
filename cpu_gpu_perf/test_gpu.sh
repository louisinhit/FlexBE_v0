for b in 1 2 4 6 8 10
do
    python3 torch_fp16_bfly_nn_gpu.py --batch $b --gpu 2 --log gpu_precision_log.txt
done
