#FROM nvidia/cuda-ppc64le:8.0-cudnn5-devel-ubuntu16.04
FROM nvidia/cuda-ppc64le:8.0-cudnn6-devel-ubuntu16.04
#FROM nvidia/cuda-ppc64le:9.0-cudnn7-devel-ubuntu16.04


MAINTAINER Abhijit Thatte <abhijit.thatte@aricent.com>

RUN apt-get update && apt-get install -y \
        autoconf \
        libtool \
        build-essential \
        curl \
        git \
        graphviz \
	libfreetype6-dev \
        libhdf5-serial-dev \
        libhdf5-dev \
        libopencv-dev \
        libopencv-gpu-dev \
        libopencv-highgui-dev \
        libpng12-dev \
        libzmq3-dev \
        pkg-config \
        python3-dev \
        python3-numpy \
        python-opencv \
        python3-pip \
        python3-skimage \
        software-properties-common \
        swig \
        zip \
        zlib1g-dev \
        libcurl3-dev \
        openjdk-8-jdk \
        openjdk-8-jre-headless \
        libblas-dev \
        liblapack-dev \
        libatlas-base-dev \
        gfortran \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*

RUN curl -fSsL -O https://bootstrap.pypa.io/get-pip.py && \
    python3 get-pip.py && \
    rm get-pip.py

RUN pip3 install grpcio

RUN pip3 --no-cache-dir install \
        Cython \
        ipykernel \
        graphviz \
        h5py \
        jupyter \
        keras \
        matplotlib \
        numpy \
        pandas \
        pydot \
        scikit-image \
        scipy \
        seaborn \
        sklearn \
        statsmodels \
        && python3 -m ipykernel.kernelspec

RUN update-ca-certificates -f

RUN git clone -b ppc-protobuf https://github.com/ai-infra/protobuf-ppc64le.git /protobuf

RUN cd /protobuf && \
  ./autogen.sh && \
  ./configure --prefix=/opt/DL/protobuf && \
  make && \
  make install

ENV PROTOC /opt/DL/protobuf/bin/protoc
ENV CXXFLAGS -I/opt/DL/protobuf/include
ENV LDFLAGS -L/opt/DL/protobuf/lib/

RUN git clone -b ppc-grpc https://github.com/ai-infra/grpc-java-ppc64le.git /grpc-java

RUN cd /grpc-java && \
   ./gradlew build --info -Pprotoc=$PROTOC -PprotoInclude="/opt/DL/protobuf/include/" -PprotoLib="/opt/DL/protobuf/lib" --continue || true

ENV GRPC_JAVA_PLUGIN=/grpc-java/compiler/build/artifacts/java_plugin/protoc-gen-grpc-java.exe

#*RUN git clone -b ppc-bazel https://github.com/ai-infra/bazel-ppc64le.git /bazel

RUN apt-get update && apt-get install -y \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir bazel \
    && cd bazel \
    && wget https://github.com/bazelbuild/bazel/releases/download/0.4.5/bazel-0.4.5-dist.zip \
    && unzip bazel-0.4.5-dist.zip

WORKDIR /bazel

RUN ./compile.sh

RUN cp output/bazel /usr/bin

#*RUN cd /bazel && \
#*    echo "build --spawn_strategy=standalone --genrule_strategy=standalone" >>/tmp/.bazelrc && \
#*    BAZELRC=/tmp/bazelrc ./compile.sh && \
#*    cp output/bazel  /usr/bin/

RUN mkdir /output

# Configure the build for our CUDA configuration.
ENV CI_BUILD_PYTHON python3
ENV LD_LIBRARY_PATH /usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH
ENV TF_NEED_CUDA 1
ENV TF_CUDA_COMPUTE_CAPABILITIES=3.0,3.5,5.2,6.0,6.1

# Copy the cudnn header file to the desired location
RUN mkdir /usr/lib/powerpc64le-linux-gnu/include/
RUN cp /usr/include/cudnn.h /usr/lib/powerpc64le-linux-gnu/include/

RUN git clone https://github.com/tensorflow/tensorflow /tensorflow

RUN cd /tensorflow && \
#*    git checkout v1.0.1 && \
    git checkout v1.3.1 && \
    git checkout -b latest-stable && \
    tensorflow/tools/ci_build/builds/configured GPU && \
    bazel build -j `nproc` --ram_utilization_factor 50 -c opt --config=cuda //tensorflow/tools/pip_package:build_pip_package && \
    bazel-bin/tensorflow/tools/pip_package/build_pip_package /output && \
    rm -rf /tmp/pip && \
    rm -rf /root/.cache

WORKDIR /

RUN rm -rf /tensorflow /grpc-java /protobuf /bazel

RUN pip3 install /output/tensorflow*.whl

WORKDIR /notebooks

RUN cd $WORKDIR \
    && git clone https://github.com/waleedka/coco \
    && cd coco/PythonAPI \
    && sed -i 's/python/python3/g' Makefile \
    && make \
    && make install \
    && python3 setup.py install

CMD jupyter-notebook --ip="*" --no-browser --allow-root
