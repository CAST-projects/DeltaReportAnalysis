<?xml version="1.0" encoding="iso-8859-1" standalone="no"?>
<Package DatabaseKind="KB_LOCAL" Description="Delta Analysis" Display="Delta Analysis" PackName="DELTA_ANALYSIS" SupportedServer="ALL" Type="SPECIFIC" Version="1.0.0.1000">
	<Include>
	</Include>
	<Exclude>
	</Exclude>
	<Install>
		<Step File="table_delta_analysis.xml" Option="512" Scope="DELTA_ANALYSIS" Type="XML_MODEL"/>
	</Install>
	<Update>
		<!--<Step Type="XML_MODEL" Option="4" File="table_delta_analysis.xml" Scope="UPDATED_820_822_DELTA_ANALYSIS" ToVersion="8.2.2.0"/> -->
		<Step File="DeltaAnalysis.sql" Type="PROC"/>
	</Update>
	<Refresh>
		<!--<Step File="table_delta_analysis.xml" Option="512" Scope="DELTA_ANALYSIS" Type="XML_MODEL"/>-->
		<Step File="DeltaAnalysis.sql" Type="PROC"/>
	</Refresh>
	<Remove>
	</Remove>
</Package>
