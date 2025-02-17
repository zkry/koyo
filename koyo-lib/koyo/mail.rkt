#lang racket/base

(require component
         postmark
         racket/contract
         racket/format
         racket/function
         racket/generic
         racket/hash
         racket/string
         "url.rkt"
         "util.rkt")


;; Adapters ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 mail-adapter?
 mail-adapter-send-email-with-template)

(define-logger mail-adapter)

(define-generics mail-adapter
  (mail-adapter-send-email-with-template
   mail-adapter
   #:to to
   #:from from
   #:template-id [template-id]
   #:template-alias [template-alias]
   #:template-model template-model))


;; Stub adapter ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 make-stub-mail-adapter
 stub-mail-adapter?
 stub-mail-adapter-outbox)

(struct stub-mail-adapter (queue)
  #:methods gen:mail-adapter
  [(define (mail-adapter-send-email-with-template ma
                                                  #:to to
                                                  #:from from
                                                  #:template-id [template-id #f]
                                                  #:template-alias [template-alias #f]
                                                  #:template-model template-model)
     (unless (or template-id template-alias)
       (raise-user-error 'mail-adapter-send-email-with-template
                         "either template-id or template-alias must be provided"))

     (define message
       (hasheq 'to to
               'from from
               'template (or template-id template-alias)
               'template-model template-model))

     (box-swap! (stub-mail-adapter-queue ma) (curry cons message))
     (log-mail-adapter-info "templated email added to outbox ~v" message))])

(define/contract (make-stub-mail-adapter)
  (-> mail-adapter?)
  (stub-mail-adapter (box null)))

(define/contract (stub-mail-adapter-outbox ma)
  (-> stub-mail-adapter? (listof hash?))
  (unbox (stub-mail-adapter-queue ma)))


;; Postmark adapter ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 postmark-mail-adapter?
 make-postmark-mail-adapter)

(struct postmark-mail-adapter (client)
  #:methods gen:mail-adapter
  [(define (mail-adapter-send-email-with-template ma
                                                  #:to to
                                                  #:from from
                                                  #:template-id [template-id #f]
                                                  #:template-alias [template-alias #f]
                                                  #:template-model template-model)
     (void
      (postmark-send-email-with-template
       (postmark-mail-adapter-client ma)
       #:to to
       #:from from
       #:template-id template-id
       #:template-alias template-alias
       #:template-model template-model)))])

(define/contract (make-postmark-mail-adapter client)
  (-> postmark? mail-adapter?)
  (postmark-mail-adapter client))


;; Mailer ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 make-mailer-factory
 mailer?
 mailer-adapter
 mailer-sender
 mailer-common-variables
 mailer-merge-common-variables)

(struct mailer (adapter sender common-variables)
  #:methods gen:component
  [(define component-start identity)
   (define component-stop identity)])

(define/contract ((make-mailer-factory #:adapter adapter
                                       #:sender sender
                                       #:common-variables common-variables))
  (-> #:adapter mail-adapter?
      #:sender non-empty-string?
      #:common-variables (hash/c symbol? string?)
      (-> mailer?))
  (mailer adapter sender common-variables))

(define/contract (mailer-merge-common-variables m . variables)
  (-> mailer? any/c ... (hash/c symbol? string?))
  (hash-union
   (mailer-common-variables m)
   (apply hasheq variables)
   #:combine/key (lambda (k _ v) v)))
