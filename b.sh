#!/bin/bash

# Script by TIMISONG-dev

# Начало отсчета времени выполнения скрипта
start_time=$(date +%s)

# Удаление каталога "out", если он существует
rm -rf out

# Основной каталог
MAINPATH=/workspaces # измените, если необходимо

# Каталог ядра
KERNEL_DIR=$MAINPATH
KERNEL_PATH=$KERNEL_DIR/pk_xiaomi_sm8250

# Каталоги компиляторов
CLANG_DIR=/lib/llvm-21
ANDROID_PREBUILTS_GCC_ARM_DIR=$KERNEL_DIR/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9
ANDROID_PREBUILTS_GCC_AARCH64_DIR=$KERNEL_DIR/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9

# Проверка и клонирование, если необходимо
check_and_clone() {
    local dir=$1
    local repo=$2

    if [ ! -d "$dir" ]; then
        echo "Папка $dir не существует. Клонирование $repo."
        git clone $repo $dir
    fi
}

check_and_wget() {
    local dir=$1
    local repo=$2

    if [ ! -d "$dir" ]; then
        echo "Папка $dir не существует. Клонирование $repo."
        mkdir $dir
        cd $dir
        wget $repo
        tar -zxvf Clang-21.0.0git-20250322.tar.gz
        rm -rf Clang-21.0.0git-20250322.tar.gz
        cd ../kernel_xiaomi_sm8250
    fi
}

# Клонирование инструментов компиляции, если они не существуют
check_and_clone $ANDROID_PREBUILTS_GCC_ARM_DIR https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9
check_and_clone $ANDROID_PREBUILTS_GCC_AARCH64_DIR https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9

# Установка переменных PATH
PATH=$CLANG_DIR/bin:$ANDROID_PREBUILTS_GCC_AARCH64_DIR/bin:$ANDROID_PREBUILTS_GCC_ARM_DIR/bin:$PATH
export PATH
export ARCH=arm64

# Каталог для сборки PureKernel
if [ "$DEVICE" = "munch" ]; then
    PURE_KERNEL_DIR="$KERNEL_DIR/pk"
else
    PURE_KERNEL_DIR="$KERNEL_DIR/pk"
fi

# Создание каталога PureKernel, если его нет
if [ ! -d "$PURE_KERNEL_DIR" ]; then
    mkdir -p "$PURE_KERNEL_DIR"
    
    # Проверка и клонирование Anykernel, если PureKernel не существует
    if [ ! -d "$PURE_KERNEL_DIR/Anykernel" ]; then
        git clone https://github.com/olzhas0986/Anykernel.git "$PURE_KERNEL_DIR/Anykernel"
        
        # Перемещение всех файлов из Anykernel в PureKernel
        mv "$PURE_KERNEL_DIR/Anykernel/"* "$PURE_KERNEL_DIR/"
        
        # Удаление папки Anykernel
        rm -rf "$PURE_KERNEL_DIR/Anykernel"
    fi
else
    # Если папка PureKernel существует, проверить наличие .git и удалить, если есть
    if [ -d "$PURE_KERNEL_DIR/.git" ]; then
        rm -rf "$PURE_KERNEL_DIR/.git"
    fi
fi

# Экспорт переменных среды
export IMGPATH="$PURE_KERNEL_DIR/Image"
export DTBPATH="$PURE_KERNEL_DIR/dtb"
export DTBOPATH="$PURE_KERNEL_DIR/dtbo.img"
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
export KBUILD_BUILD_USER="olzhas0986"
export KBUILD_BUILD_HOST="dev"

# Запись времени сборки
PURE_BUILD_DATE=$(date '+%m-%d_%H-%M-%S')

# Каталог для результатов сборки
output_dir=out

# Конфигурация ядра
make O="$output_dir" \
            munch_defconfig

    # Компиляция ядра
    make -j $(nproc) \
                O="$output_dir" \
                CC="ccache clang" \
                HOSTCC=gcc \
                LD=ld.lld \
                AS=llvm-as \
                AR=llvm-ar \
                NM=llvm-nm \
                OBJCOPY=llvm-objcopy \
                OBJDUMP=llvm-objdump \
                STRIP=llvm-strip \
                LLVM=1 \
                LLVM_IAS=1 \
                V=$VERBOSE 2>&1 | tee build.log
                

# Предполагается, что переменная DTS установлена ранее в скрипте
find $DTS -name '*.dtb' -exec cat {} + > $DTBPATH
find $DTS -name 'Image' -exec cat {} + > $IMGPATH
find $DTS -name 'dtbo.img' -exec cat {} + > $DTBOPATH

# Завершение отсчета времени выполнения скрипта
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

cd "$KERNEL_PATH"

# Проверка успешности сборки
if grep -q -E "Ошибка 2|Error 2" build.log; then
    cd "$KERNEL_PATH"
    echo "Ошибка: Сборка завершилась с ошибкой"
else
    echo "Общее время выполнения: $elapsed_time секунд"
    # Перемещение в каталог PureKernel и создание архива
    cd "$PURE_KERNEL_DIR"
    7z a -mx9 PK-$PURE_BUILD_DATE.zip * -x!*.zip
    
    BUILD=$((BUILD + 1))
fi
