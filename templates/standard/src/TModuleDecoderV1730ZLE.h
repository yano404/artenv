/**
 * @file	TModuleDecoderV1730ZLE.h
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
 
#ifndef TMODULEDECODERV1730ZLE_H
#define TMODULEDECODERV1730ZLE_H

#include <TModuleDecoder.h>


namespace art {
	class TModuleDecoderV1730ZLE;
}

class art::TModuleDecoderV1730ZLE  : public TModuleDecoder {
	public:
		static const int kID = 61;
		static const UShort_t fSkippedSampleValue = 20000; //-1;
	protected:
		Int_t fVerboseLevel; // verbose level

	public:
		TModuleDecoderV1730ZLE();
		virtual ~TModuleDecoderV1730ZLE();
		virtual Int_t Decode(char* buffer, const int &size, TObjArray *seg);
		ClassDef(TModuleDecoderV1730ZLE,0); // decoder for V1730ZLE
};
#endif // end of #ifdef TMODULEDECODERV1730ZLE_H
