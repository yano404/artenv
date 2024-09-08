/**
 * @file	TModuleDecoderV1730ZLE.cc
 *
 * @brief	Decoder for CAEN V1730(DPP-ZLE firmware)
 * 
 * @date   Created       : 2023.01.03
 *         Last Modified : 2023.01.04
 *
 * @author Takayuki YANO
 *
 * Copylight 2023 Takayuki YANO
 */

#include "TModuleDecoderV1730ZLE.h"
#include <TRawDataFadc.h>

art::TModuleDecoderV1730ZLE::TModuleDecoderV1730ZLE()
	: TModuleDecoder(kID,TRawDataFadc::Class())
{
}
art::TModuleDecoderV1730ZLE::~TModuleDecoderV1730ZLE()
{
}

Int_t art::TModuleDecoderV1730ZLE::Decode(char* buf, const int &size, TObjArray *seg)
{
	unsigned int *evtdata = (unsigned int *) buf;
	unsigned int evtsize = size / sizeof(unsigned int);
	unsigned int ts, pattern;
	int offset = 0;
	int geo;
	const int nch = 16;
	int uch = 0;

	/* Check and read header (evtadata[0:3]) */
	// Check if the data starts with 0b1010
	// printf("%x\n", evtdata[0]);
	if (((evtdata[0]>>28)&0xf)!=0b1010) {
		//printf("Invalid Value: Data does not started with 0b1010\n");
		return -1;
	}

	// Read BOARD ID
	geo = ((evtdata[1]>>27)&0x1f);

	// Read PATTERN/TRG OPTIONS
	pattern = ((evtdata[1]>>8)&0xffff);

	// Read CHANNEL MASK
	int chmask = evtdata[1] & 0x000000ff;
	chmask += (evtdata[2] & 0xff000000)>>16;
	// Check the number of used channels
	for (int i=0; i<nch; i++) {
		if (((chmask>>i)&0x1) == 1) {
			uch++;
		}
	}
	if (uch == 0) {
		printf("No channel");
		return -1;
	}

	// Read TTT
	ts = evtdata[3];

	/* Read Event Data */
	unsigned int i = 4; // evtdata[0:4]=headers evtdata[4:]=data
	int ch;
	int chwordsize = 0;
	int skippedsize = 0;
	while (i<evtsize) {
		// Read channel
		for (ch=0; ch<nch; ch++) {
			if ((chmask&0x1) == 1) {
				// Get size
				chwordsize = evtdata[i]&0x0000ffff;

				// Initialize data
				TRawDataFadc* data = (TRawDataFadc*) New();
				data->Clear("C");
				data->SetSegInfo(seg->GetUniqueID(), geo, ch);
				data->SetFadcInfo(ts, offset, pattern);
				// Read channel samples
				for (int j=0; j<chwordsize; j++) {
					i++;
					//if (((evtdata[i]>>31)&0x1) == 1) {
					if (((evtdata[i]>>27)&0xf) == 0x8) {
						// Skipped samples
						skippedsize = 2*(evtdata[i]&0x0fffffff);
                        //printf("%x\n", evtdata[i]&0xffffffff);
						for (int k=0; k<skippedsize; k++) {
							data->Add(fSkippedSampleValue);
						}
					} else {
						// Read SAMPLE[n] - CH[x]
						data->Add(evtdata[i]&0x00003fff);
						// Read SAMPLE[n+1] - CH[x]
						data->Add((evtdata[i]&0x03fff0000)>>16);
					}
				}
				seg->Add(data);
			}
			chmask=chmask>>1;
		}
	}
	return 0;
}
