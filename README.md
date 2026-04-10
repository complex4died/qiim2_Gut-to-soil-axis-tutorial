qiime2 gut-to-soil 流程， 优化版
> 原教程：<https://amplicon-docs.qiime2.org/en/stable/tutorials/gut-to-soil.html#BXKp4yAIUR>

- 环境(docker):
```shell
$ docker images | grep "qiime2"
WARNING: This output is designed for human readability. For machine-readable output, please use --format.
quay.io/qiime2/amplicon:2026.1   d4ddc1d2fe43       10.4GB         2.79GB   U
```
- qiime2版本: amplicon:2026.1


```shell
# 1. 环境准备与目录初始化

## 1.1 创建工作空间
mkdir -p 00_raw_data 01_qc 02_denoise 03_taxonomy 04_phylogeny 05_diversity 06_exported

## 1.2 确保 Docker 容器能正常调用 qiime2
docker run -it --rm \
  -v "$(pwd)":/data -w /data \
  quay.io/qiime2/amplicon:2026.1 \
  qiime info


# 2. 数据准备与质控 (Quality Control)

## 2.1 数据导入
wget -O '00_raw_data/sample-metadata.tsv' \
  'https://gut-to-soil-tutorial.readthedocs.io/en/stable/data/gut-to-soil/sample-metadata.tsv'

wget -O '00_raw_data/demux.qza' \
  'https://gut-to-soil-tutorial.readthedocs.io/en/stable/data/gut-to-soil/demux.qza'


## 2.2 原始数据质量检查
### 进入环境
docker run -it --rm \
  -v "$(pwd)":/data \
  -w /data \
  quay.io/qiime2/amplicon:2026.1 \
  bash

### qc
qiime demux summarize \
  --i-data 00_raw_data/demux.qza \
  --o-visualization 01_qc/demux.qzv


# 3. 序列去噪 (DADA2)
rm -rf 02_denoise/
qiime dada2 denoise-paired \
  --i-demultiplexed-seqs 00_raw_data/demux.qza \
  --p-trunc-len-f 250 \
  --p-trunc-len-r 250 \
  --output-dir 02_denoise/

## 3.1 特征表过滤 (可选但推荐)
#--- 过滤掉只在 1 个样本中出现的 ASVs（单次观测值），提高数据稳健性。
qiime feature-table filter-features \
  --i-table 02_denoise/table.qza \
  --p-min-samples 2 \
  --o-filtered-table 02_denoise/table-filtered.qza


# 4. 分类学注释与进化树构建
## 4.1 物种注释 (Taxonomy)
wget -O '00_raw_data/suboptimal-16S-rRNA-classifier.qza' \
  'https://gut-to-soil-tutorial.readthedocs.io/en/stable/data/gut-to-soil/suboptimal-16S-rRNA-classifier.qza'

CLASSIFIER=00_raw_data/suboptimal-16S-rRNA-classifier.qza
#classifier.qza 为训练好的数据库一般需要自己去训练

qiime feature-classifier classify-sklearn \
  --i-classifier $CLASSIFIER \
  --i-reads 02_denoise/representative_sequences.qza \
  --o-classification 03_taxonomy/taxonomy.qza

#---生成物种组成柱状图
qiime taxa barplot \
  --i-table 02_denoise/table-filtered.qza \
  --i-taxonomy 03_taxonomy/taxonomy.qza \
  --m-metadata-file 00_raw_data/sample-metadata.tsv \
  --o-visualization 03_taxonomy/taxa-bar-plots.qzv

## 4.2 构建进化树
#---为后续计算加权 UniFrac 距离做准备
rm -rf 04_phylogeny/
qiime phylogeny align-to-tree-mafft-fasttree \
  --i-sequences 02_denoise/representative_sequences.qza \
  --output-dir 04_phylogeny/


# 5. 多样性分析 (Diversity)
#--- 注意：--p-sampling-depth 需要根据 table.qzv 的结果来确定
rm -rf 05_diversity/
qiime diversity core-metrics-phylogenetic \
  --i-phylogeny 04_phylogeny/rooted_tree.qza \
  --i-table 02_denoise/table-filtered.qza \
  --p-sampling-depth 100 \
  --m-metadata-file 00_raw_data/sample-metadata.tsv \
  --output-dir 05_diversity/


# 6. 数据导出 (Export for R/microeco)
#---导出特征表并转为 TSV
rm -rf 06_exported/
qiime tools export \
 --input-path 02_denoise/table-filtered.qza \
 --output-path 06_exported/

biom convert \
 -i 06_exported/feature-table.biom \
 -o 06_exported/asv_table.tsv \
 --to-tsv

#---导出物种注释
qiime tools export \
--input-path 03_taxonomy/taxonomy.qza \
--output-path 06_exported/

#---导出进化树 (用于 R 中的系统发育分析)
qiime tools export \
  --input-path 04_phylogeny/rooted_tree.qza \
  --output-path 06_exported/

# 退出
exit

```

最终结果：
```shell
$ tree
.
├── 00_raw_data
│   ├── demux.qza
│   ├── sample-metadata.tsv
│   └── suboptimal-16S-rRNA-classifier.qza
├── 01_qc
│   └── demux.qzv
├── 02_denoise
│   ├── base_transition_stats.qza
│   ├── denoising_stats.qza
│   ├── representative_sequences.qza
│   ├── table-filtered.qza
│   └── table.qza
├── 03_taxonomy
│   ├── taxa-bar-plots.qzv
│   └── taxonomy.qza
├── 04_phylogeny
│   ├── alignment.qza
│   ├── masked_alignment.qza
│   ├── rooted_tree.qza
│   └── tree.qza
├── 05_diversity
│   ├── bray_curtis_distance_matrix.qza
│   ├── bray_curtis_emperor.qzv
│   ├── bray_curtis_pcoa_results.qza
│   ├── evenness_vector.qza
│   ├── faith_pd_vector.qza
│   ├── jaccard_distance_matrix.qza
│   ├── jaccard_emperor.qzv
│   ├── jaccard_pcoa_results.qza
│   ├── observed_features_vector.qza
│   ├── rarefied_table.qza
│   ├── shannon_vector.qza
│   ├── unweighted_unifrac_distance_matrix.qza
│   ├── unweighted_unifrac_emperor.qzv
│   ├── unweighted_unifrac_pcoa_results.qza
│   ├── weighted_unifrac_distance_matrix.qza
│   ├── weighted_unifrac_emperor.qzv
│   └── weighted_unifrac_pcoa_results.qza
└── 06_exported
    ├── asv_table.tsv
    ├── feature-table.biom
    ├── taxonomy.tsv
    └── tree.nwk

8 directories, 36 files

```

主要文件夹为 **06_exported**

- asv_table.tsv (asv表) 
- taxonomy.tsv  (注释结果表)
- tree.nwk      (系统进化树)
