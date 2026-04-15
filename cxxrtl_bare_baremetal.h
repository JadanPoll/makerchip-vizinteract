// A bare-metal port that includes the absolute minimal stuff for code to work. DOES NOT USE C Standard library, debug and $print simulation statements removed
// only with -nostdlib
// Notes: Instaniates 16MB for potential RAM use(maximum wasm limit). There are probably tons of optimizations in here
// Notes: You can easily inline this in your code so dont have to deal with CORS annoyances. I just really want a most-stable version that wont change.
// Notes: If there's any feature you want but not in this, look at the reference for whats supported, you can then do the necessary translation to patch it in
/* Notes: Generating .VCD and debugging are possible but not implmenet because frankly im not too invested in those features and force our hand
  into finding and impelementing more workarounds for the STL. Its doable if you implement some other stuff in the reference however. Be prepared for a lot of work though!
  In the future, I will make sure to document every singular thing this baremetal implementation leaves out from the original
*/
#ifndef BARE_CXXRTL_H
#define BARE_CXXRTL_H

#define CXXRTL_EXTREMELY_COLD
#define CXXRTL_ALWAYS_INLINE inline

typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
typedef int int32_t;
typedef long long int64_t;
typedef unsigned long size_t;

#ifndef UINT32_C
#define UINT32_C(c) c ## U
#endif
#ifndef UINT64_C
#define UINT64_C(c) c ## ULL
#endif

// --- MOCK THE STL FOR YOSYS STUBS ---
namespace std {
    template<typename T> struct remove_reference { typedef T type; };
    template<typename T> struct remove_reference<T&> { typedef T type; };
    template<typename T> struct remove_reference<T&&> { typedef T type; };

    template<class E> class initializer_list {
        const E* _M_array; size_t _M_len;
    public:
        constexpr initializer_list(const E* a, size_t l) : _M_array(a), _M_len(l) {}
        constexpr initializer_list() : _M_array(nullptr), _M_len(0) {}
        constexpr size_t size() const { return _M_len; }
        constexpr const E* begin() const { return _M_array; }
        constexpr const E* end() const { return _M_array + _M_len; }
    };
    template<typename T> struct unique_ptr {
        T* p;
        unique_ptr() : p(nullptr) {}
        unique_ptr(T* ptr) : p(ptr) {}
        ~unique_ptr() { delete p; }
        T* operator->() const { return p; }
        T& operator*() const { return *p; }
        void reset(T* ptr) { delete p; p = ptr; }
        unique_ptr(unique_ptr&& o) : p(o.p) { o.p = nullptr; }
        unique_ptr& operator=(unique_ptr&& o) { delete p; p = o.p; o.p = nullptr; return *this; }
    };
    template<typename T> struct unique_ptr<T[]> {
        T* p;
        unique_ptr() : p(nullptr) {}
        unique_ptr(T* ptr) : p(ptr) {}
        ~unique_ptr() { delete[] p; }
        T& operator[](size_t i) const { return p[i]; }
        unique_ptr(unique_ptr&& o) : p(o.p) { o.p = nullptr; }
        unique_ptr& operator=(unique_ptr&& o) { delete[] p; p = o.p; o.p = nullptr; return *this; }
    };
    struct string {
        string() {} string(const char*) {}
        bool empty() const { return true; } size_t size() const { return 0; }
        string substr(size_t, size_t) const { return *this; } char operator[](size_t) const { return 0; }
    };
    template<typename T> T&& move(T& x) { return static_cast<T&&>(x); }
    template<typename... Args> int bind(Args&&...) { return 0; }
    template<bool B, class T = void> struct enable_if {};
    template<class T> struct enable_if<true, T> { typedef T type; };
    template<typename T> struct make_unsigned { typedef uint32_t type; }; 
    template<> struct make_unsigned<int64_t> { typedef uint64_t type; };
    template<class T1, class T2> struct pair { T1 first; T2 second; pair(T1 a, T2 b) : first(a), second(b) {} pair() {} };
}

typedef void* cxxrtl_toplevel;
struct _cxxrtl_toplevel { template<typename T> _cxxrtl_toplevel(T) {} };

namespace cxxrtl {
    using chunk_t = uint32_t;
    using wide_chunk_t = uint64_t;
    struct interior {};

    struct metadata_pair { template<typename K, typename V> metadata_pair(K, V) {} };
    struct metadata_map { metadata_map() {} metadata_map(std::initializer_list<metadata_pair>) {} };
    struct debug_item { enum { INPUT=1, OUTPUT=2, INOUT=3, UNDRIVEN=4, DRIVEN_SYNC=8, DRIVEN_COMB=16, GENERATED=32 }; };
    struct debug_items { template<typename... Args> void add(Args&&...) {} };
    struct debug_scopes { template<typename... Args> void add(Args&&...) {} };
    struct debug_outline { debug_outline() {} template<typename T> debug_outline(T) {} };

    template<class T> struct expr_base;

    // --- VALUE DEFINITION ---
    template<size_t Bits>
    struct value : public expr_base<value<Bits>> {
        static constexpr size_t bits = Bits;
        static constexpr size_t chunks = (Bits + 31) / 32;
        static constexpr chunk_t msb_mask = (Bits % 32 == 0) ? ~0u : (~0u >> (32 - Bits % 32));

        chunk_t data[chunks] = {};
        
        value() = default;
        template<typename... Init> constexpr value(Init ...init) : data{static_cast<chunk_t>(init)...} {}
        
        CXXRTL_ALWAYS_INLINE bool operator==(const value& o) const {
            for (size_t i = 0; i < chunks; ++i) if (data[i] != o.data[i]) return false;
            return true;
        }
        CXXRTL_ALWAYS_INLINE bool operator!=(const value& o) const { return !(*this == o); }
        operator bool() const { return !is_zero(); }
        bool is_zero() const { for (size_t i = 0; i < chunks; ++i) if (data[i]) return false; return true; }
        bool is_neg() const { return data[chunks - 1] & (1u << ((Bits - 1) % 32)); }
        
        size_t ctlz() const {
            size_t count = 0;
            for (size_t n = 0; n < chunks; n++) {
                chunk_t x = data[chunks - 1 - n];
                count += (n == 0 ? (Bits % 32 ? Bits % 32 : 32) : 32);
                if (x != 0) { for (; x != 0; count--) x >>= 1; break; }
            }
            return count;
        }
        size_t ctpop() const {
            size_t count = 0;
            for (size_t n = 0; n < chunks; n++) { for (chunk_t x = data[n]; x != 0; count++) x = x & (x - 1); }
            return count;
        }

        // Bitwise
        CXXRTL_ALWAYS_INLINE value bit_not() const { value r; for(size_t i=0; i<chunks; i++) r.data[i] = ~data[i]; r.data[chunks-1] &= msb_mask; return r; }
        CXXRTL_ALWAYS_INLINE value bit_and(const value &o) const { value r; for(size_t i=0; i<chunks; i++) r.data[i] = data[i] & o.data[i]; return r; }
        CXXRTL_ALWAYS_INLINE value bit_or(const value &o) const { value r; for(size_t i=0; i<chunks; i++) r.data[i] = data[i] | o.data[i]; return r; }
        CXXRTL_ALWAYS_INLINE value bit_xor(const value &o) const { value r; for(size_t i=0; i<chunks; i++) r.data[i] = data[i] ^ o.data[i]; return r; }
        
        // Math & Arithmetic
        CXXRTL_ALWAYS_INLINE value add(const value &o) const {
            value r; uint64_t c = 0;
            for (size_t i = 0; i < chunks; i++) { uint64_t t = (uint64_t)data[i] + o.data[i] + c; r.data[i] = (uint32_t)t; c = t >> 32; }
            r.data[chunks - 1] &= msb_mask; return r;
        }
        CXXRTL_ALWAYS_INLINE value sub(const value &o) const {
            value r; uint64_t c = 1;
            for (size_t i = 0; i < chunks; i++) { uint64_t t = (uint64_t)data[i] + ~o.data[i] + c; r.data[i] = (uint32_t)t; c = t >> 32; }
            r.data[chunks - 1] &= msb_mask; return r;
        }
        template<size_t R> CXXRTL_ALWAYS_INLINE value<R> mul(const value &o) const {
            value<R> r; wide_chunk_t tmp[value<R>::chunks + 1] = {};
            for (size_t i = 0; i < chunks; i++) 
                for (size_t j = 0; j < o.chunks && i + j < r.chunks; j++) {
                    tmp[i + j] += (wide_chunk_t)data[i] * o.data[j];
                    tmp[i + j + 1] += tmp[i + j] >> 32; tmp[i + j] &= ~0u;
                }
            for (size_t i = 0; i < r.chunks; i++) r.data[i] = (uint32_t)tmp[i];
            r.data[r.chunks - 1] &= r.msb_mask; return r;
        }
        CXXRTL_ALWAYS_INLINE value neg() const { return value().sub(*this); }
        bool ucmp(const value &o) const { bool c = true; for(size_t i=0; i<chunks; i++) { uint64_t r = (uint64_t)data[i] + ~o.data[i] + c; c = r >> 32; } return !c; }
        bool scmp(const value &o) const {
            value r; bool c = true;
            for(size_t i=0; i<chunks; i++) { uint64_t sum = (uint64_t)data[i] + ~o.data[i] + c; r.data[i] = (uint32_t)sum; c = sum >> 32; }
            bool overflow = (is_neg() == !o.is_neg()) && (is_neg() != r.is_neg());
            return r.is_neg() ^ overflow;
        }

        std::pair<value, value> udivmod(value divisor) const {
            value q, d = *this; if (d.ucmp(divisor)) return {value{0u}, d};
            int64_t shift = divisor.ctlz() - d.ctlz(); divisor = divisor.shl(value{(chunk_t)shift});
            for (int i = 0; i <= shift; i++) {
                q = q.shl(value{1u}); if (!d.ucmp(divisor)) { d = d.sub(divisor); q.data[0] |= 1; }
                divisor = divisor.shr(value{1u});
            }
            return {q, d};
        }
        std::pair<value, value> sdivmod(const value &o) const {
            value<Bits+1> q, r, d_ext = sext<Bits+1>(), o_ext = o.template sext<Bits+1>();
            if (is_neg()) d_ext = d_ext.neg(); if (o.is_neg()) o_ext = o_ext.neg();
            auto res = d_ext.udivmod(o_ext); q = res.first; r = res.second;
            if (is_neg() != o.is_neg()) q = q.neg(); if (is_neg()) r = r.neg();
            return {q.template trunc<Bits>(), r.template trunc<Bits>()};
        }

        // Extenders
        template<size_t NewBits> CXXRTL_ALWAYS_INLINE value<NewBits> trunc() const {
            value<NewBits> r; for (size_t i = 0; i < (r.chunks < chunks ? r.chunks : chunks); i++) r.data[i] = data[i];
            r.data[r.chunks - 1] &= r.msb_mask; return r;
        }
        template<size_t NewBits> CXXRTL_ALWAYS_INLINE value<NewBits> zext() const {
            value<NewBits> r; for (size_t i = 0; i < chunks; i++) r.data[i] = data[i]; return r;
        }
        template<size_t NewBits> CXXRTL_ALWAYS_INLINE value<NewBits> sext() const {
            value<NewBits> r = zext<NewBits>();
            if (is_neg()) { for (size_t i = chunks; i < r.chunks; i++) r.data[i] = ~0u; r.data[r.chunks-1] &= r.msb_mask; }
            return r;
        }
        template<size_t NewBits> CXXRTL_ALWAYS_INLINE value<NewBits> rtrunc() const {
            value<NewBits> r; size_t sc = (Bits - NewBits) / 32, sb = (Bits - NewBits) % 32;
            chunk_t c = (sc + r.chunks < chunks && sb) ? data[sc + r.chunks] << (32 - sb) : 0;
            for (size_t i = r.chunks; i > 0; i--) { r.data[i - 1] = c | (data[sc + i - 1] >> sb); c = sb ? data[sc + i - 1] << (32 - sb) : 0; }
            return r;
        }
        template<size_t NewBits> CXXRTL_ALWAYS_INLINE value<NewBits> rzext() const {
            value<NewBits> r; size_t sc = (NewBits - Bits) / 32, sb = (NewBits - Bits) % 32; chunk_t c = 0;
            for (size_t i = 0; i < chunks; i++) { r.data[sc + i] = (data[i] << sb) | c; c = sb ? data[i] >> (32 - sb) : 0; }
            if (sc + chunks < r.chunks) r.data[sc + chunks] = c; return r;
        }

        template<size_t N> CXXRTL_ALWAYS_INLINE value<N> zcast() const {
            if constexpr (N > Bits) return zext<N>(); else return trunc<N>();
        }
        template<size_t N> CXXRTL_ALWAYS_INLINE value<N> scast() const {
            if constexpr (N > Bits) return sext<N>(); else return trunc<N>();
        }

        // Shifts
        template<size_t A> CXXRTL_ALWAYS_INLINE value shl(const value<A> &amt) const {
            value r; size_t s = amt.data[0], sc = s / 32, sb = s % 32; if (sc >= chunks) return r;
            uint64_t c = 0; for (size_t i = 0; i < chunks - sc; i++) { uint64_t t = ((uint64_t)data[i] << sb) | c; r.data[i + sc] = (uint32_t)t; c = t >> 32; }
            r.data[chunks - 1] &= msb_mask; return r;
        }
        template<size_t A> CXXRTL_ALWAYS_INLINE value shr(const value<A> &amt) const {
            value r; size_t s = amt.data[0], sc = s / 32, sb = s % 32; if (sc >= chunks) return r;
            uint64_t c = 0; for (size_t i = 0; i < chunks - sc; i++) {
                size_t idx = chunks - 1 - i; r.data[idx - sc] = (data[idx] >> sb) | c;
                c = sb ? (uint64_t)data[idx] << (32 - sb) : 0;
            }
            return r;
        }
        template<size_t A> CXXRTL_ALWAYS_INLINE value sshr(const value<A> &amt) const {
            value r = shr(amt); if (!is_neg()) return r;
            size_t s = amt.data[0]; if (s >= Bits) s = Bits;
            for (size_t i = Bits - s; i < Bits; i++) r.data[i / 32] |= (1u << (i % 32));
            return r;
        }

        // Hardware Multiplexers
        CXXRTL_ALWAYS_INLINE value<Bits> bwmux(const value<Bits> &b, const value<Bits> &s) const {
            return (bit_and(s.bit_not())).bit_or(b.bit_and(s));
        }
        template<size_t ResultBits, size_t SelBits> value<ResultBits> bmux(const value<SelBits> &sel) const {
            size_t amount = sel.data[0] * ResultBits, sc = amount / 32, sb = amount % 32;
            value<ResultBits> r; chunk_t c = 0;
            if (ResultBits % 32 + sb > 32) c = data[r.chunks + sc] << (32 - sb);
            for (size_t n = 0; n < r.chunks; n++) {
                r.data[r.chunks - 1 - n] = c | (data[r.chunks + sc - 1 - n] >> sb);
                c = sb ? data[r.chunks + sc - 1 - n] << (32 - sb) : 0;
            }
            r.data[r.chunks - 1] &= r.msb_mask; return r;
        }
        template<size_t ResultBits, size_t SelBits> value<ResultBits> demux(const value<SelBits> &sel) const {
            size_t amount = sel.data[0] * Bits, sc = amount / 32, sb = amount % 32;
            value<ResultBits> r; chunk_t c = 0;
            for (size_t n = 0; n < chunks; n++) { r.data[sc + n] = (data[n] << sb) | c; c = sb ? data[n] >> (32 - sb) : 0; }
            if (Bits % 32 + sb > 32) r.data[sc + chunks] = c; return r;
        }

        // The Corrected Blit
        template<size_t Stop, size_t Start>
        CXXRTL_ALWAYS_INLINE value blit(const value<Stop-Start+1>& src) const {
            value r = *this;
            constexpr size_t W = Stop - Start + 1;
            size_t sc = Start / 32, sb = Start % 32;
            size_t affected = (W + sb + 31) / 32;

            for (size_t i = 0; i < affected; i++) {
                size_t idx = sc + i; if (idx >= chunks) break;
                uint32_t mask = 0u;
                if (i == 0) mask |= ~(~0u << sb);
                if (i == affected - 1) {
                    size_t end_bits = (sb + W) % 32;
                    if (end_bits != 0) mask |= (~0u << end_bits);
                }
                r.data[idx] &= mask;
            }
            for (size_t i = 0; i < src.chunks; i++) {
                uint64_t t = (uint64_t)src.data[i] << sb;
                if (sc + i < chunks) r.data[sc + i] |= (uint32_t)t;
                if (sc + i + 1 < chunks) r.data[sc + i + 1] |= (uint32_t)(t >> 32);
            }
            return r;
        }

        template<size_t Count> value<Bits * Count> repeat() const {
            value<Bits * Count> r; if (!is_zero()) { for(size_t i=0; i<r.chunks; i++) r.data[i] = ~0U; r.data[r.chunks-1] &= r.msb_mask; }
            return r;
        }
        
        const value& val() const { return *this; }
        template<class T> T get() const { return static_cast<T>(data[0]); }
    };

    // --- EXPRESSION TEMPLATES ---
    template<class T, size_t Stop, size_t Start> struct slice_expr : public expr_base<slice_expr<T, Stop, Start>> {
        static constexpr size_t bits = Stop - Start + 1; T &expr; slice_expr(T &e) : expr(e) {}
        typedef typename std::remove_reference<T>::type T_base;
        operator value<bits>() const { return static_cast<const value<T_base::bits>&>(expr).template rtrunc<T_base::bits-Start>().template trunc<bits>(); }
        slice_expr& operator=(const value<bits>& rhs) { expr = static_cast<const value<T_base::bits>&>(expr).template blit<Stop, Start>(rhs); return *this; }
        value<bits> val() const { return operator value<bits>(); }
    };
    template<class T, class U> struct concat_expr : public expr_base<concat_expr<T, U>> {
        typedef typename std::remove_reference<T>::type T_base; typedef typename std::remove_reference<U>::type U_base;
        static constexpr size_t bits = T_base::bits + U_base::bits; T &ms; U &ls; concat_expr(T &m, U &l) : ms(m), ls(l) {}
        operator value<bits>() const {
            value<bits> m_s = static_cast<const value<T_base::bits>&>(ms).template rzext<bits>(), l_e = static_cast<const value<U_base::bits>&>(ls).template zext<bits>(), r;
            for(size_t i=0; i<value<bits>::chunks; i++) r.data[i] = m_s.data[i] | l_e.data[i]; return r;
        }
        value<bits> val() const { return operator value<bits>(); }
    };
    template<class T> struct expr_base {
        template<size_t Stop, size_t Start = Stop> slice_expr<const T, Stop, Start> slice() const { return {*static_cast<const T *>(this)}; }
        template<size_t Stop, size_t Start = Stop> slice_expr<T, Stop, Start> slice() { return {*static_cast<T *>(this)}; }
        template<class U> concat_expr<const T, const U> concat(const U &other) const { return {*static_cast<const T *>(this), other}; }
        template<class U> concat_expr<T, U> concat(U &&other) { return {*static_cast<T *>(this), other}; }
    };

    template<size_t Bits> struct wire {
        value<Bits> curr, next; wire() = default; constexpr wire(const value<Bits>& v) : curr(v), next(v) {}
        template<class Obs> bool commit(Obs&) { if (curr != next) { curr = next; return true; } return false; }
        bool commit() { if (curr != next) { curr = next; return true; } return false; }
    };

    // Parameterized dynamic memory using driver Bump Allocator
    template<size_t Width> struct memory { 
        size_t depth; 
        std::unique_ptr<value<Width>[]> data; 
        struct write { size_t i; value<Width> v, m; } q[64]; size_t qn = 0;
        explicit memory(size_t d) : depth(d), data(new value<Width>[d]) {}
        value<Width> &operator[](size_t i) { return data[i]; }
        const value<Width> &operator[](size_t i) const { return data[i]; }
        void update(size_t i, value<Width> v, value<Width> m, int priority=0) { if(qn < 64) q[qn++] = {i, v, m}; }
        template<class Obs> bool commit(Obs&) { 
            bool ch = false; for(size_t k=0; k<qn; k++) { 
                value<Width> n = data[q[k].i].bit_and(q[k].m.bit_not()).bit_or(q[k].v.bit_and(q[k].m)); 
                if(data[q[k].i] != n) ch = true; data[q[k].i] = n; 
            } 
            qn = 0; return ch; 
        }
    };

    struct performer { virtual ~performer() {} };
    struct observer  { virtual ~observer() {} };

    struct module {
        virtual ~module() {} virtual void reset() = 0; virtual bool eval(performer* = nullptr) = 0; virtual bool commit() = 0;
        size_t step(performer* p = nullptr) { size_t deltas = 0; bool converged = false; do { converged = eval(p); deltas++; } while (commit() && !converged); return deltas; }
        virtual void debug_info(debug_items*, debug_scopes*, std::string, metadata_map&& = {}) {}
    };
} // cxxrtl

namespace cxxrtl_yosys {
    using namespace cxxrtl;
    
    template<class T> CXXRTL_ALWAYS_INLINE constexpr T max(const T &a, const T &b) { return a > b ? a : b; }

    struct memory_index {
        bool valid;
        size_t index;
        template<size_t BitsAddr>
        memory_index(const value<BitsAddr> &addr, size_t offset, size_t depth) {
            size_t offset_index = addr.data[0];
            valid = (offset_index >= offset && offset_index < offset + depth);
            index = offset_index - offset;
        }
    };

    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> logic_not(const value<A> &a) { return value<Y>{ a.is_zero() ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> logic_or(const value<A> &a, const value<B> &b) { return value<Y>{ (!a.is_zero() || !b.is_zero()) ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> logic_and(const value<A> &a, const value<B> &b) { return value<Y>{ (!a.is_zero() && !b.is_zero()) ? 1u : 0u }; }
    
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> reduce_bool(const value<A> &a) { return value<Y>{ a.is_zero() ? 0u : 1u }; }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> reduce_and(const value<A> &a) { return value<Y>{ a.bit_not().is_zero() ? 1u : 0u }; }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> reduce_or(const value<A> &a) { return value<Y>{ a.is_zero() ? 0u : 1u }; }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> reduce_xor(const value<A> &a) { return value<Y>{ (a.ctpop() % 2) ? 1u : 0u }; }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> reduce_xnor(const value<A> &a) { return value<Y>{ (a.ctpop() % 2) ? 0u : 1u }; }

    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> not_u(const value<A> &a) { return a.template zcast<Y>().bit_not(); }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> not_s(const value<A> &a) { return a.template scast<Y>().bit_not(); }

    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> and_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().bit_and(b.template zcast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> and_ss(const value<A>& a, const value<B>& b) { return a.template scast<Y>().bit_and(b.template scast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> or_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().bit_or(b.template zcast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> or_ss(const value<A>& a, const value<B>& b) { return a.template scast<Y>().bit_or(b.template scast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> xor_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().bit_xor(b.template zcast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> xor_ss(const value<A>& a, const value<B>& b) { return a.template scast<Y>().bit_xor(b.template scast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> xnor_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().bit_xor(b.template zcast<Y>()).bit_not(); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> xnor_ss(const value<A>& a, const value<B>& b) { return a.template scast<Y>().bit_xor(b.template scast<Y>()).bit_not(); }

    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> add_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().add(b.template zcast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> add_ss(const value<A>& a, const value<B>& b) { return a.template scast<Y>().add(b.template scast<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> sub_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().sub(b.template zext<Y>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> sub_ss(const value<A>& a, const value<B>& b) { return a.template scast<Y>().sub(b.template scast<Y>()); }
    
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> mul_uu(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return a.template zcast<Ext>().template mul<Y>(b.template zcast<Ext>()); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> mul_ss(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return a.template scast<Ext>().template mul<Y>(b.template scast<Ext>()); }
    
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> div_uu(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return a.template zcast<Ext>().udivmod(b.template zcast<Ext>()).first.template trunc<Y>(); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> div_ss(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return a.template scast<Ext>().sdivmod(b.template scast<Ext>()).first.template trunc<Y>(); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> mod_uu(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return a.template zcast<Ext>().udivmod(b.template zcast<Ext>()).second.template trunc<Y>(); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> mod_ss(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return a.template scast<Ext>().sdivmod(b.template scast<Ext>()).second.template trunc<Y>(); }
    
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> modfloor_uu(const value<A> &a, const value<B> &b) { return mod_uu<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> modfloor_ss(const value<A> &a, const value<B> &b) {
        auto res = a.template scast<max(A,B)>().sdivmod(b.template scast<max(A,B)>());
        if((b.is_neg() != a.is_neg()) && !res.second.is_zero()) return b.template scast<Y>().add(res.second.template trunc<Y>());
        return res.second.template trunc<Y>();
    }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> divfloor_uu(const value<A> &a, const value<B> &b) { return div_uu<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> divfloor_ss(const value<A> &a, const value<B> &b) {
        auto res = a.template scast<max(A,B)>().sdivmod(b.template scast<max(A,B)>());
        if ((b.is_neg() != a.is_neg()) && !res.second.is_zero()) return res.first.template trunc<Y>().sub(value<Y>{1u});
        return res.first.template trunc<Y>();
    }

    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shl_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().shl(b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> sshl_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().shl(b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shl_su(const value<A>& a, const value<B>& b) { return a.template scast<Y>().shl(b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> sshl_su(const value<A>& a, const value<B>& b) { return a.template scast<Y>().shl(b); }
    
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shr_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().shr(b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> sshr_uu(const value<A>& a, const value<B>& b) { return a.template zcast<Y>().sshr(b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shr_su(const value<A>& a, const value<B>& b) { return a.template scast<Y>().shr(b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> sshr_su(const value<A>& a, const value<B>& b) { return a.template scast<Y>().sshr(b); }

    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shift_uu(const value<A> &a, const value<B> &b) { return shr_uu<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shift_su(const value<A> &a, const value<B> &b) { return shr_su<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shift_us(const value<A> &a, const value<B> &b) { return b.is_neg() ? shl_uu<Y>(a, b.template sext<B + 1>().neg()) : shr_uu<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shift_ss(const value<A> &a, const value<B> &b) { return b.is_neg() ? shl_su<Y>(a, b.template sext<B + 1>().neg()) : shr_su<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shiftx_uu(const value<A> &a, const value<B> &b) { return shift_uu<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shiftx_su(const value<A> &a, const value<B> &b) { return shift_su<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shiftx_us(const value<A> &a, const value<B> &b) { return shift_us<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> shiftx_ss(const value<A> &a, const value<B> &b) { return shift_ss<Y>(a, b); }

    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> eq_uu(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return value<Y>{a.template zcast<Ext>() == b.template zcast<Ext>() ? 1u : 0u}; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> eq_ss(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return value<Y>{a.template scast<Ext>() == b.template scast<Ext>() ? 1u : 0u}; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> ne_uu(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y>{ a.template zcast<Ext>() != b.template zcast<Ext>() ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> ne_ss(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y>{ a.template scast<Ext>() != b.template scast<Ext>() ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> eqx_uu(const value<A> &a, const value<B> &b) { return eq_uu<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> eqx_ss(const value<A> &a, const value<B> &b) { return eq_ss<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> nex_uu(const value<A> &a, const value<B> &b) { return ne_uu<Y>(a, b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> nex_ss(const value<A> &a, const value<B> &b) { return ne_ss<Y>(a, b); }

    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> gt_uu(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return value<Y>{b.template zcast<Ext>().ucmp(a.template zcast<Ext>()) ? 1u : 0u}; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> gt_ss(const value<A>& a, const value<B>& b) { constexpr size_t Ext = max(A, B); return value<Y>{b.template scast<Ext>().scmp(a.template scast<Ext>()) ? 1u : 0u}; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> ge_uu(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y> { !a.template zcast<Ext>().ucmp(b.template zcast<Ext>()) ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> ge_ss(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y> { !a.template scast<Ext>().scmp(b.template scast<Ext>()) ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> lt_uu(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y> { a.template zcast<Ext>().ucmp(b.template zcast<Ext>()) ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> lt_ss(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y> { a.template scast<Ext>().scmp(b.template scast<Ext>()) ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> le_uu(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y> { !b.template zcast<Ext>().ucmp(a.template zcast<Ext>()) ? 1u : 0u }; }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> le_ss(const value<A> &a, const value<B> &b) { constexpr size_t Ext = max(A, B); return value<Y> { !b.template scast<Ext>().scmp(a.template scast<Ext>()) ? 1u : 0u }; }

    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> pos_u(const value<A> &a) { return a.template zcast<Y>(); }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> pos_s(const value<A> &a) { return a.template scast<Y>(); }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> neg_u(const value<A> &a) { return a.template zcast<Y>().neg(); }
    template<size_t Y, size_t A> CXXRTL_ALWAYS_INLINE value<Y> neg_s(const value<A> &a) { return a.template scast<Y>().neg(); }

    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> bmux(const value<A> &a, const value<B> &b) { return a.template bmux<Y>(b); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> bwmux(const value<A> &a, const value<A> &b, const value<B> &c) { return a.bwmux(b, c); }
    template<size_t Y, size_t A, size_t B> CXXRTL_ALWAYS_INLINE value<Y> demux(const value<A> &a, const value<B> &b) { return a.template demux<Y>(b); }
}
#define assert(x)
// Nathan: Sometimes it looks for this so we have this here
#ifndef CXXRTL_ASSERT
#ifndef CXXRTL_NDEBUG
#define CXXRTL_ASSERT(x) assert(x)
#else
#define CXXRTL_ASSERT(x)
#endif
#endif
#endif
