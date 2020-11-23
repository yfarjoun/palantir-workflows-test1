version 1.0

workflow IdentifyContaminantArrayTest {
	input {
		File contaminated_vcf
		File contaminant_vcf
		File other_vcf
		Float contamination_estimate

		File haplotype_database
		File ref
		File ref_index
		File ref_dict
	}

	call IdentifyContaminant {
		input:
			vcf = contaminated_vcf,
			haplotype_database = haplotype_database,
			ref = ref,
			contamination = contamination_estimate,
			ref_index = ref_index,
			ref_dict = ref_dict
	}

	call Crosscheck as CrosscheckAgainstContaminant {
		input:
			vcf1 = IdentifyContaminant.extracted_contam_fp,
			vcf2 = contaminant_vcf,
			haplotype_database = haplotype_database
	}

	call Crosscheck as CrosscheckAgainstOther {
		input:
			vcf1 = IdentifyContaminant.extracted_contam_fp,
			vcf2 = other_vcf,
			haplotype_database = haplotype_database
	}

	call ExtractLODScore as ExtractLODScoreAgainstContaminant {
		input:
			crosscheck_output = CrosscheckAgainstContaminant.crosscheck_output
	}

	call ExtractLODScore as ExtractLODScoreAgainstOther {
		input:
			crosscheck_output = CrosscheckAgainstOther.crosscheck_output
	}

	output {
		File crosscheck_against_contaminant = CrosscheckAgainstContaminant.crosscheck_output
		File crosscheck_against_other = CrosscheckAgainstOther.crosscheck_output
		Float lod_score_against_contaminant = ExtractLODScoreAgainstContaminant.lod_score
		Float lod_score_against_other = ExtractLODScoreAgainstOther.lod_score
		File extracted_contaminant_fp=IdentifyContaminant.extracted_contam_fp
	}

}

task ExtractLODScore {
	input {
		File crosscheck_output
	}

	command <<<
		set -xeuo pipefail

		Rscript -<<"EOF"
			library(dplyr)
			library(readr)

			t <- read_tsv("~{crosscheck_output}", comment = "#")
			write(t%>%pull(LOD_SCORE), "crosscheck_value.txt")
		EOF
	>>>

	runtime {
		docker: "rocker/tidyverse"
		disks: "local-disk 100 HDD"
	}

	output {
		Float lod_score = read_float("crosscheck_value.txt")
	}
}

task IdentifyContaminant {
	input {
		File vcf
		File haplotype_database
		File ref
		File ref_index
		File ref_dict
		Float contamination

		File picard_jar = "gs://broad-dsde-methods-ckachulis/jars/picard_identify_contaminant_array_cloud.jar"
	}

	parameter_meta {
		vcf : {
			localization_optional : true
		}
	}

	Int disk_size = ceil(size(haplotype_database, "GB") + size(ref, "GB") + size(picard_jar, "GB")) + 50

	command <<<
		set -xeuo pipefail

		java -jar ~{picard_jar} IdentifyContaminant I=~{vcf} O=extracted_contam_fp.vcf.gz H=~{haplotype_database} C=~{contamination} R=~{ref}
	>>>

	runtime {
	docker: "broadinstitute/picard:2.23.4"
	disks: "local-disk " + disk_size + " HDD"
	memory: "16 GB"
  }
  output {
	File extracted_contam_fp = "extracted_contam_fp.vcf.gz"
	File extracted_contam_fp_index = "extracted_contam_fp.vcf.gz.tbi"
  }
}

task Crosscheck {
	input {
		File vcf1
		File vcf2
		File haplotype_database

		File picard_jar = "gs://broad-dsde-methods-ckachulis/jars/picard_identify_contaminant_array_cloud.jar"
	}

	parameter_meta {
		vcf1 : {
			localization_optional : true
		}
		vcf2 : {
			localization_optional : true
		}
	}

	Int disk_size = ceil(size(haplotype_database, "GB") + size(vcf1, "GB") + size(vcf2, "GB") + size(picard_jar, "GB")) + 50

	command <<<
		set -xeuo pipefail

		java -jar ~{picard_jar} CrosscheckFingerprints I=~{vcf1} SI=~{vcf2} CROSSCHECK_MODE=CHECK_ALL_OTHERS CROSSCHECK_BY=SAMPLE H=~{haplotype_database} O=croscheck.metrics EXIT_CODE_WHEN_MISMATCH=0
	>>>

	runtime {
		docker: "broadinstitute/picard:2.23.4"
		disks: "local-disk " + disk_size + " HDD"
		memory: "16 GB"
  	}

  	output {
  		File crosscheck_output = "croscheck.metrics"
  	}
}