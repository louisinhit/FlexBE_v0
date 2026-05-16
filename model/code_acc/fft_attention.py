import torch
import torch.nn as nn
from functools import partial


class FNetBasicFourierTransform(nn.Module):
    def __init__(self):
        super().__init__()
        self._init_fourier_transform()

    def _init_fourier_transform(self):
        self.fourier_transform = partial(torch.fft.fftn, dim=(1, 2))

    def forward(self, hidden_states):

        # NOTE: We do not use torch.vmap as it is not integrated into PyTorch stable versions.
        # Interested users can modify the code to use vmap from the nightly versions, getting the vmap from here:
        # https://pytorch.org/docs/master/generated/torch.vmap.html. Note that fourier transform methods will need
        # change accordingly.

        outputs = self.fourier_transform(hidden_states).real
        #outputs = torch.abs(self.fourier_transform(hidden_states))
        return outputs