/*
 * @file TModuleDecoderMIRAQDC.h
 * @date  Created : 2024.05.17 (T.Yano)
 *  Last Modified : 2024.05.17 (T.Yano)
 */
#ifndef TMODULEDECODERMIRAQDC_H
#define TMODULEDECODERMIRAQDC_H
#include <TModuleDecoder.h>

namespace art {
  class TModuleDecoderMIRAQDC;
}

class art::TModuleDecoderMIRAQDC  : public TModuleDecoder {
  public:
    static const int kID = 49;

    TModuleDecoderMIRAQDC();
    explicit TModuleDecoderMIRAQDC(Int_t id);
    virtual ~TModuleDecoderMIRAQDC();
    virtual Int_t Decode(char* buffer, const int &size, TObjArray *seg);

  protected:
    TObjArray *fHitData; // array to temporally store the data for the aggregation

  private:
    TModuleDecoderMIRAQDC(const TModuleDecoderMIRAQDC&);
    TModuleDecoderMIRAQDC& operator=(const TModuleDecoderMIRAQDC&);

    ClassDef(TModuleDecoderMIRAQDC,0) 
};
#endif // TMODULEDECODERMIRAQDC_H
