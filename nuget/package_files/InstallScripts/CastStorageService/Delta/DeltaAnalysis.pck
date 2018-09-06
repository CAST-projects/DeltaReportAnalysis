<?xml version="1.0" encoding="iso-8859-1" standalone="no"?>
<Package DatabaseKind="KB_LOCAL" Description="Delta Analysis" Display="Delta Analysis" PackName="DELTA_ANALYSIS" SupportedServer="ALL" Type="SPECIFIC" Version="1.1.0">
	<Include>
	</Include>
	<Exclude>
	</Exclude>
	<Install>
		<Step File="table_delta_analysis.xml" Option="512" Scope="DELTA_ANALYSIS" Type="XML_MODEL"/>
    <Step File="table_check_results.xml" Option="512" Scope="DELTA_CHECKS" Type="XML_MODEL"/>
	</Install>
	<Update>
		<Step Type="XML_MODEL" Option="4" File="table_check_results.xml" Scope="DELTA_CHECKS" ToVersion="1.1.0"/> -->
	</Update>
	<Refresh>
		<Step File="DeltaAnalysis.sql" Type="PROC"/>
    <Step File="CheckAnalysisResults.sql" Type="PROC"/>
	</Refresh>
	<Remove>
	</Remove>
</Package>
