/*
 * @file TModuleDecoderFIT.h
 * @date  Created : 2024.09.08 (T.Yano)
 *  Last Modified : 2024.09.08 (T.Yano)
 */
#ifndef TMODULEDECODERFIT_H
#define TMODULEDECODERFIT_H
#include <TModuleDecoder.h>

namespace art {
  class TModuleDecoderFIT;
}

class art::TModuleDecoderFIT  : public TModuleDecoder {
  public:
    static const int kID = 47;

    TModuleDecoderFIT();
    explicit TModuleDecoderFIT(Int_t id);
    virtual ~TModuleDecoderFIT();
    virtual Int_t Decode(char* buffer, const int &size, TObjArray *seg);

  protected:
    TObjArray *fHitData; // array to temporally store the data for the aggregation

  private:
    TModuleDecoderFIT(const TModuleDecoderFIT&);
    TModuleDecoderFIT& operator=(const TModuleDecoderFIT&);

    ClassDef(TModuleDecoderFIT,0) 
};
#endif // TMODULEDECODERFIT_H
