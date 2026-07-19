// Lean compiler output
// Module: NoEscalation.Semantics
// Imports: public import Init public meta import Init public import NoEscalation.Kernel
#include <lean/lean.h>
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wunused-label"
#elif defined(__GNUC__) && !defined(__CLANG__)
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#endif
#ifdef __cplusplus
extern "C" {
#endif
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx___redArg(lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx___redArg___boxed(lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx___boxed(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorElim___redArg(lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorElim(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorElim___boxed(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_idle_elim___redArg(lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_idle_elim(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_active_elim___redArg(lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_active_elim(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx___redArg(lean_object* v_x_1_){
_start:
{
if (lean_obj_tag(v_x_1_) == 0)
{
lean_object* v___x_2_; 
v___x_2_ = lean_unsigned_to_nat(0u);
return v___x_2_;
}
else
{
lean_object* v___x_3_; 
v___x_3_ = lean_unsigned_to_nat(1u);
return v___x_3_;
}
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx___redArg___boxed(lean_object* v_x_4_){
_start:
{
lean_object* v_res_5_; 
v_res_5_ = lp_NoEscalation_NoEscalation_Phase_ctorIdx___redArg(v_x_4_);
lean_dec(v_x_4_);
return v_res_5_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx(lean_object* v_E_6_, lean_object* v_Comp_7_, lean_object* v_x_8_){
_start:
{
lean_object* v___x_9_; 
v___x_9_ = lp_NoEscalation_NoEscalation_Phase_ctorIdx___redArg(v_x_8_);
return v___x_9_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorIdx___boxed(lean_object* v_E_10_, lean_object* v_Comp_11_, lean_object* v_x_12_){
_start:
{
lean_object* v_res_13_; 
v_res_13_ = lp_NoEscalation_NoEscalation_Phase_ctorIdx(v_E_10_, v_Comp_11_, v_x_12_);
lean_dec(v_x_12_);
return v_res_13_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorElim___redArg(lean_object* v_t_14_, lean_object* v_k_15_){
_start:
{
if (lean_obj_tag(v_t_14_) == 0)
{
return v_k_15_;
}
else
{
lean_object* v_performer_16_; lean_object* v_ctx_17_; lean_object* v___x_18_; 
v_performer_16_ = lean_ctor_get(v_t_14_, 0);
lean_inc(v_performer_16_);
v_ctx_17_ = lean_ctor_get(v_t_14_, 1);
lean_inc_ref(v_ctx_17_);
lean_dec_ref_known(v_t_14_, 2);
v___x_18_ = lean_apply_2(v_k_15_, v_performer_16_, v_ctx_17_);
return v___x_18_;
}
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorElim(lean_object* v_E_19_, lean_object* v_Comp_20_, lean_object* v_motive_21_, lean_object* v_ctorIdx_22_, lean_object* v_t_23_, lean_object* v_h_24_, lean_object* v_k_25_){
_start:
{
lean_object* v___x_26_; 
v___x_26_ = lp_NoEscalation_NoEscalation_Phase_ctorElim___redArg(v_t_23_, v_k_25_);
return v___x_26_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_ctorElim___boxed(lean_object* v_E_27_, lean_object* v_Comp_28_, lean_object* v_motive_29_, lean_object* v_ctorIdx_30_, lean_object* v_t_31_, lean_object* v_h_32_, lean_object* v_k_33_){
_start:
{
lean_object* v_res_34_; 
v_res_34_ = lp_NoEscalation_NoEscalation_Phase_ctorElim(v_E_27_, v_Comp_28_, v_motive_29_, v_ctorIdx_30_, v_t_31_, v_h_32_, v_k_33_);
lean_dec(v_ctorIdx_30_);
return v_res_34_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_idle_elim___redArg(lean_object* v_t_35_, lean_object* v_idle_36_){
_start:
{
lean_object* v___x_37_; 
v___x_37_ = lp_NoEscalation_NoEscalation_Phase_ctorElim___redArg(v_t_35_, v_idle_36_);
return v___x_37_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_idle_elim(lean_object* v_E_38_, lean_object* v_Comp_39_, lean_object* v_motive_40_, lean_object* v_t_41_, lean_object* v_h_42_, lean_object* v_idle_43_){
_start:
{
lean_object* v___x_44_; 
v___x_44_ = lp_NoEscalation_NoEscalation_Phase_ctorElim___redArg(v_t_41_, v_idle_43_);
return v___x_44_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_active_elim___redArg(lean_object* v_t_45_, lean_object* v_active_46_){
_start:
{
lean_object* v___x_47_; 
v___x_47_ = lp_NoEscalation_NoEscalation_Phase_ctorElim___redArg(v_t_45_, v_active_46_);
return v___x_47_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Phase_active_elim(lean_object* v_E_48_, lean_object* v_Comp_49_, lean_object* v_motive_50_, lean_object* v_t_51_, lean_object* v_h_52_, lean_object* v_active_53_){
_start:
{
lean_object* v___x_54_; 
v___x_54_ = lp_NoEscalation_NoEscalation_Phase_ctorElim___redArg(v_t_51_, v_active_53_);
return v___x_54_;
}
}
lean_object* initialize_Init(uint8_t builtin);
lean_object* initialize_Init(uint8_t builtin);
lean_object* initialize_NoEscalation_NoEscalation_Kernel(uint8_t builtin);
static bool _G_initialized = false;
LEAN_EXPORT lean_object* initialize_NoEscalation_NoEscalation_Semantics(uint8_t builtin) {
lean_object * res;
if (_G_initialized) return lean_io_result_mk_ok(lean_box(0));
_G_initialized = true;
res = initialize_Init(builtin);
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Init(builtin);
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_NoEscalation_NoEscalation_Kernel(builtin);
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
return lean_io_result_mk_ok(lean_box(0));
}
#ifdef __cplusplus
}
#endif
