#!/bin/bash

# ==============================================================================
# QIIME 2 Amplicon Analysis Pipeline (Docker Version)
# Description: Standardized workflow for 16S/ITS rRNA sequencing data.
# License: MIT
# ==============================================================================

# --- 1. 配置区域 ---
# 这里的参数可以根据实际项目需求修改
IMAGE_NAME="quay.io/qiime2/amplicon:2026.1"
SAMPLING_DEPTH=100
TRUNC_LEN_F=250
TRUNC_LEN_R=250
THREADS=10  # 建议根据服务器核心数调整

# --- 2. 环境初始化 ---
echo ">>>> [1/6] Initializing directories..."
mkdir -p 00_raw_data 01_qc 02_denoise 03_taxonomy 04_phylogeny 05_diversity 06_exported

# --- 3. 定义 Docker 运行宏 (简化后续代码) ---
# 使用 -u $(id -u):$(id -g) 确保生成的文件权限属于当前用户，而不是 root
DOCKER_RUN="docker run --rm -u $(id -u):$(id -g) -v $(pwd):/data -w /data $IMAGE_NAME"

# --- 4. 数据准备 ---
echo ">>>> [2/6] Preparing data..."
if [ ! -f "00_raw_data/demux.qza" ]; then
    echo "Downloading tutorial data..."
    wget -P 00_raw_data/ https://gut-to-soil-tutorial.readthedocs.io/en/stable/data/gut-to-soil/sample-metadata.tsv
    wget -P 00_raw_data/ https://gut-to-soil-tutorial.readthedocs.io/en/stable/data/gut-to-soil/demux.qza
    wget -P 00_raw_data/ https://gut-to-soil-tutorial.readthedocs.io/en/stable/data/gut-to-soil/suboptimal-16S-rRNA-classifier.qza
fi

# --- 5. 执行分析流 ---

# 5.1 质量检查
echo ">>>> [3/6] Running Quality Control (demux summarize)..."
$DOCKER_RUN qiime demux summarize \
  --i-data 00_raw_data/demux.qza \
  --o-visualization 01_qc/demux.qzv

# 5.2 去噪 (DADA2)
echo ">>>> [4/6] Denoising with DADA2 (this may take a while)..."
$DOCKER_RUN qiime dada2 denoise-paired \
  --i-demultiplexed-seqs 00_raw_data/demux.qza \
  --p-trunc-len-f $TRUNC_LEN_F \
  --p-trunc-len-r $TRUNC_LEN_R \
  --p-n-threads $THREADS \
  --output-dir 02_denoise/

# 5.3 特征表过滤
$DOCKER_RUN qiime feature-table filter-features \
  --i-table 02_denoise/table.qza \
  --p-min-samples 2 \
  --o-filtered-table 02_denoise/table-filtered.qza

# 5.4 物种注释与进化树
echo ">>>> [5/6] Taxonomy classification & Phylogeny construction..."
$DOCKER_RUN qiime feature-classifier classify-sklearn \
  --i-classifier 00_raw_data/suboptimal-16S-rRNA-classifier.qza \
  --i-reads 02_denoise/representative_sequences.qza \
  --o-classification 03_taxonomy/taxonomy.qza

$DOCKER_RUN qiime taxa barplot \
  --i-table 02_denoise/table-filtered.qza \
  --i-taxonomy 03_taxonomy/taxonomy.qza \
  --m-metadata-file 00_raw_data/sample-metadata.tsv \
  --o-visualization 03_taxonomy/taxa-bar-plots.qzv

$DOCKER_RUN qiime phylogeny align-to-tree-mafft-fasttree \
  --i-sequences 02_denoise/representative_sequences.qza \
  --output-dir 04_phylogeny/ \
  --p-n-threads $THREADS

# 5.5 多样性分析
echo ">>>> [6/6] Diversity analysis (Depth: $SAMPLING_DEPTH)..."
$DOCKER_RUN qiime diversity core-metrics-phylogenetic \
  --i-phylogeny 04_phylogeny/rooted_tree.qza \
  --i-table 02_denoise/table-filtered.qza \
  --p-sampling-depth $SAMPLING_DEPTH \
  --m-metadata-file 00_raw_data/sample-metadata.tsv \
  --output-dir 05_diversity/

# --- 6. 数据导出 (下游分析专用) ---
echo ">>>> Exporting final TSV and Newick files for R/microeco..."

$DOCKER_RUN qiime tools export --input-path 02_denoise/table-filtered.qza --output-path 06_exported/
$DOCKER_RUN biom convert -i 06_exported/feature-table.biom -o 06_exported/asv_table.tsv --to-tsv
$DOCKER_RUN qiime tools export --input-path 03_taxonomy/taxonomy.qza --output-path 06_exported/
$DOCKER_RUN qiime tools export --input-path 04_phylogeny/rooted_tree.qza --output-path 06_exported/

# 重命名导出的物种文件以避免冲突
mv 06_exported/taxonomy.tsv 06_exported/taxonomy_raw.tsv 2>/dev/null

echo "=============================================================================="
echo "Pipeline Finished Successfully!"
echo "Main results are located in: 06_exported/"
echo "=============================================================================="