import os
#os.environ['PYOPENCL_CTX']='0:1'
os.environ['PYOPENCL_COMPILER_OUTPUT'] = '0'
#os.environ['CUDA_PROFILE'] = '1'
import chroma.api as api
#api.use_cuda()
api.use_opencl()
if api.is_gpu_api_cuda():
    import pycuda.driver as cuda
    import chroma.gpu.cutools as cutools
elif api.is_gpu_api_opencl():
    import pyopencl as cl
    import chroma.gpu.cltools as cltools
else:
    raise RuntimeError('API not set to either CUDA or OpenCL')
import chroma.gpu.tools as tools
from photon_fromstep import GPUPhotonFromSteps
import numpy as np


context = tools.get_context()

steps = np.load( 'steps.npy' )
photons = GPUPhotonFromSteps( steps, cl_context=context )

pos = photons.pos.get()
print pos[400:450]
context.pop()
