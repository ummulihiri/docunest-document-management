;; docunest-core
;; 
;; This contract manages document ownership, metadata, collections, and access permissions
;; for the DocuNest document management system. It stores document references and metadata
;; on-chain while the actual content remains in decentralized storage (IPFS/Gaia).
;; 
;; The contract enables users to:
;; 1. Create and manage document collections (similar to folders)
;; 2. Add document references with metadata
;; 3. Set granular access permissions for documents and collections
;; 4. Track document version history

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-COLLECTION-NOT-FOUND (err u101))
(define-constant ERR-DOCUMENT-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-PARAMS (err u104))
(define-constant ERR-UNKNOWN-PERMISSION (err u105))

;; Permission levels
(define-constant PERMISSION-NONE u0)
(define-constant PERMISSION-VIEW u1)
(define-constant PERMISSION-EDIT u2)
(define-constant PERMISSION-ADMIN u3)

;; Data maps and variables

;; Tracks all collections in the system
(define-map collections
  { collection-id: (string-ascii 36) }
  {
    name: (string-utf8 64),
    owner: principal,
    created-at: uint,
    description: (optional (string-utf8 256))
  }
)

;; Tracks all documents in the system
(define-map documents
  { document-id: (string-ascii 36) }
  {
    title: (string-utf8 128),
    description: (optional (string-utf8 256)),
    file-type: (string-ascii 16),
    storage-location: (string-utf8 256),
    content-hash: (buff 32),
    owner: principal,
    created-at: uint,
    updated-at: uint,
    size: uint,
    latest-version: uint ;; Track the latest version number
  }
)

;; Associates documents with collections (many-to-many relationship)
(define-map collection-documents
  { collection-id: (string-ascii 36), document-id: (string-ascii 36) }
  { added-at: uint }
)

;; Tracks document version history
(define-map document-versions
  { document-id: (string-ascii 36), version: uint }
  {
    content-hash: (buff 32),
    storage-location: (string-utf8 256),
    updated-at: uint,
    updated-by: principal,
    change-notes: (optional (string-utf8 256))
  }
)

;; Tracks user permissions for collections
(define-map collection-permissions
  { collection-id: (string-ascii 36), user: principal }
  { permission-level: uint }
)

;; Tracks user permissions for specific documents
(define-map document-permissions
  { document-id: (string-ascii 36), user: principal }
  { permission-level: uint }
)

;; Private functions

;; Checks if user has permission for a collection
(define-private (has-collection-permission (collection-id (string-ascii 36)) (user principal) (required-level uint))
  (let (
    (collection-info (map-get? collections { collection-id: collection-id }))
    (permission-info (map-get? collection-permissions { collection-id: collection-id, user: user }))
  )
    (if (is-none collection-info)
      false
      (if (is-eq (get owner (unwrap-panic collection-info)) user) 
        true  ;; Owner always has full permissions
        (if (is-none permission-info)
          false
          (>= (get permission-level (unwrap-panic permission-info)) required-level)
        )
      )
    )
  )
)

;; Checks if user has permission for a document
(define-private (has-document-permission (document-id (string-ascii 36)) (user principal) (required-level uint))
  (let (
    (document-info (map-get? documents { document-id: document-id }))
    (permission-info (map-get? document-permissions { document-id: document-id, user: user }))
  )
    (if (is-none document-info)
      false
      (if (is-eq (get owner (unwrap-panic document-info)) user) 
        true  ;; Owner always has full permissions
        (if (is-none permission-info)
          false
          (>= (get permission-level (unwrap-panic permission-info)) required-level)
        )
      )
    )
  )
)

;; Checks if document exists in a collection
(define-private (is-document-in-collection (collection-id (string-ascii 36)) (document-id (string-ascii 36)))
  (is-some (map-get? collection-documents { collection-id: collection-id, document-id: document-id }))
)

;; Get the latest version number for a document
(define-private (get-latest-version (document-id (string-ascii 36)))
  (default-to u0 (get updated-at (map-get? documents { document-id: document-id })))
)

;; Validate permission level
(define-private (is-valid-permission (permission-level uint))
  (and (>= permission-level PERMISSION-NONE) (<= permission-level PERMISSION-ADMIN))
)

;; Read-only functions

;; Get collection details
(define-read-only (get-collection (collection-id (string-ascii 36)))
  (map-get? collections { collection-id: collection-id })
)

;; Get document details
(define-read-only (get-document (document-id (string-ascii 36)))
  (map-get? documents { document-id: document-id })
)

;; Get document version details
(define-read-only (get-document-version (document-id (string-ascii 36)) (version uint))
  (map-get? document-versions { document-id: document-id, version: version })
)

;; Check if user has view access to a document
(define-read-only (can-view-document (document-id (string-ascii 36)) (user principal))
  (has-document-permission document-id user PERMISSION-VIEW)
)

;; Check if user has edit access to a document
(define-read-only (can-edit-document (document-id (string-ascii 36)) (user principal))
  (has-document-permission document-id user PERMISSION-EDIT)
)

;; Check if user has admin access to a collection
(define-read-only (can-admin-collection (collection-id (string-ascii 36)) (user principal))
  (has-collection-permission collection-id user PERMISSION-ADMIN)
)

;; Get all documents in a collection (returns a list of document-ids)
;; Note: In a production system, this would be implemented with pagination
;; or moved off-chain due to the potential for large lists
(define-read-only (get-documents-in-collection (collection-id (string-ascii 36)))
  (ok collection-id) ;; Placeholder - would need indexing solution in production
)

;; Public functions

;; Create a new collection
(define-public (create-collection 
    (collection-id (string-ascii 36)) 
    (name (string-utf8 64))
    (description (optional (string-utf8 256)))
  )
  (let (
    (caller tx-sender)
    (existing-collection (map-get? collections { collection-id: collection-id }))
  )
    (asserts! (is-none existing-collection) ERR-ALREADY-EXISTS)
    
    (map-set collections
      { collection-id: collection-id }
      {
        name: name,
        owner: caller,
        created-at: block-height,
        description: description
      }
    )
    
    (ok true)
  )
)

;; Add a document reference to the system
(define-public (add-document 
    (document-id (string-ascii 36))
    (title (string-utf8 128))
    (description (optional (string-utf8 256)))
    (file-type (string-ascii 16))
    (storage-location (string-utf8 256)) 
    (content-hash (buff 32))
    (size uint)
  )
  (let (
    (caller tx-sender)
    (current-time block-height)
    (existing-document (map-get? documents { document-id: document-id }))
  )
    (asserts! (is-none existing-document) ERR-ALREADY-EXISTS)
    
    ;; Create document entry
    (map-set documents
      { document-id: document-id }
      {
        title: title,
        description: description,
        file-type: file-type,
        storage-location: storage-location,
        content-hash: content-hash,
        owner: caller,
        created-at: current-time,
        updated-at: current-time,
        size: size,
        latest-version: u1
      }
    )
    
    ;; Initialize first version
    (map-set document-versions
      { document-id: document-id, version: u1 }
      {
        content-hash: content-hash,
        storage-location: storage-location,
        updated-at: current-time,
        updated-by: caller,
        change-notes: (some u"Initial version")
      }
    )
    
    (ok true)
  )
)

;; Add a document to a collection
(define-public (add-document-to-collection 
    (collection-id (string-ascii 36)) 
    (document-id (string-ascii 36))
  )
  (let (
    (caller tx-sender)
    (document-info (map-get? documents { document-id: document-id }))
    (collection-info (map-get? collections { collection-id: collection-id }))
  )
    ;; Verify document and collection exist
    (asserts! (is-some document-info) ERR-DOCUMENT-NOT-FOUND)
    (asserts! (is-some collection-info) ERR-COLLECTION-NOT-FOUND)
    
    ;; Check permissions
    (asserts! (or 
                (is-eq (get owner (unwrap-panic document-info)) caller)
                (has-document-permission document-id caller PERMISSION-EDIT)
              ) 
              ERR-NOT-AUTHORIZED)
    
    (asserts! (or 
                (is-eq (get owner (unwrap-panic collection-info)) caller)
                (has-collection-permission collection-id caller PERMISSION-EDIT)
              ) 
              ERR-NOT-AUTHORIZED)
              
    ;; Add document to collection if not already added
    (if (is-document-in-collection collection-id document-id)
      (ok true)  ;; Already in collection, no action needed
      (begin
        (map-set collection-documents
          { collection-id: collection-id, document-id: document-id }
          { added-at: block-height }
        )
        (ok true)
      )
    )
  )
)

;; Remove a document from a collection
(define-public (remove-document-from-collection 
    (collection-id (string-ascii 36)) 
    (document-id (string-ascii 36))
  )
  (let (
    (caller tx-sender)
    (document-info (map-get? documents { document-id: document-id }))
    (collection-info (map-get? collections { collection-id: collection-id }))
  )
    ;; Verify document and collection exist
    (asserts! (is-some document-info) ERR-DOCUMENT-NOT-FOUND)
    (asserts! (is-some collection-info) ERR-COLLECTION-NOT-FOUND)
    
    ;; Check permissions
    (asserts! (or 
                (is-eq (get owner (unwrap-panic document-info)) caller)
                (has-document-permission document-id caller PERMISSION-EDIT)
                (is-eq (get owner (unwrap-panic collection-info)) caller)
                (has-collection-permission collection-id caller PERMISSION-EDIT)
              ) 
              ERR-NOT-AUTHORIZED)
              
    ;; Remove document from collection
    (if (is-document-in-collection collection-id document-id)
      (begin
        (map-delete collection-documents
          { collection-id: collection-id, document-id: document-id }
        )
        (ok true)
      )
      (ok true)  ;; Not in collection, no action needed
    )
  )
)

;; Update a document (creates a new version)
(define-public (update-document 
    (document-id (string-ascii 36))
    (title (string-utf8 128))
    (description (optional (string-utf8 256)))
    (storage-location (string-utf8 256)) 
    (content-hash (buff 32))
    (size uint)
    (change-notes (optional (string-utf8 256)))
  )
  (let (
    (caller tx-sender)
    (current-time block-height)
    (document-info (unwrap! (map-get? documents { document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
  )
    ;; Verify document exists handled by unwrap!
    
    ;; Check permissions
    (asserts! (or 
                (is-eq (get owner document-info) caller)
                (has-document-permission document-id caller PERMISSION-EDIT)
              ) 
              ERR-NOT-AUTHORIZED)
    
    ;; Calculate new version number by incrementing latest
    (let ((new-version (+ u1 (get latest-version document-info))))
      
      ;; Update main document entry
      (map-set documents
        { document-id: document-id }
        (merge document-info
          {
            title: title,
            description: description,
            storage-location: storage-location,
            content-hash: content-hash,
            updated-at: current-time,
            size: size,
            latest-version: new-version ;; Update latest-version
          }
        )
      )
      
      ;; Create new version entry
      (map-set document-versions
        { document-id: document-id, version: new-version }
        {
          content-hash: content-hash,
          storage-location: storage-location,
          updated-at: current-time,
          updated-by: caller,
          change-notes: change-notes
        }
      )
      
      (ok new-version)
    )
  )
)

;; Grant permission to a user for a document
(define-public (grant-document-permission 
    (document-id (string-ascii 36)) 
    (user principal) 
    (permission-level uint)
  )
  (let (
    (caller tx-sender)
    (document-info (map-get? documents { document-id: document-id }))
  )
    ;; Verify document exists
    (asserts! (is-some document-info) ERR-DOCUMENT-NOT-FOUND)
    
    ;; Check if caller is owner
    (asserts! (is-eq (get owner (unwrap-panic document-info)) caller) ERR-NOT-AUTHORIZED)
    
    ;; Validate permission level
    (asserts! (is-valid-permission permission-level) ERR-UNKNOWN-PERMISSION)
    
    ;; Set permission
    (map-set document-permissions
      { document-id: document-id, user: user }
      { permission-level: permission-level }
    )
    
    (ok true)
  )
)

;; Grant permission to a user for a collection
(define-public (grant-collection-permission 
    (collection-id (string-ascii 36)) 
    (user principal) 
    (permission-level uint)
  )
  (let (
    (caller tx-sender)
    (collection-info (map-get? collections { collection-id: collection-id }))
  )
    ;; Verify collection exists
    (asserts! (is-some collection-info) ERR-COLLECTION-NOT-FOUND)
    
    ;; Check if caller is owner
    (asserts! (is-eq (get owner (unwrap-panic collection-info)) caller) ERR-NOT-AUTHORIZED)
    
    ;; Validate permission level
    (asserts! (is-valid-permission permission-level) ERR-UNKNOWN-PERMISSION)
    
    ;; Set permission
    (map-set collection-permissions
      { collection-id: collection-id, user: user }
      { permission-level: permission-level }
    )
    
    (ok true)
  )
)

;; Delete a document (only owner can delete)
(define-public (delete-document (document-id (string-ascii 36)))
  (let (
    (caller tx-sender)
    (document-info (map-get? documents { document-id: document-id }))
  )
    ;; Verify document exists
    (asserts! (is-some document-info) ERR-DOCUMENT-NOT-FOUND)
    
    ;; Check if caller is owner
    (asserts! (is-eq (get owner (unwrap-panic document-info)) caller) ERR-NOT-AUTHORIZED)
    
    ;; Delete document
    (map-delete documents { document-id: document-id })
    
    ;; Note: In a production system, we would also clean up all related entries
    ;; like versions and permissions, and remove from all collections
    
    (ok true)
  )
)

;; Delete a collection (only owner can delete)
(define-public (delete-collection (collection-id (string-ascii 36)))
  (let (
    (caller tx-sender)
    (collection-info (map-get? collections { collection-id: collection-id }))
  )
    ;; Verify collection exists
    (asserts! (is-some collection-info) ERR-COLLECTION-NOT-FOUND)
    
    ;; Check if caller is owner
    (asserts! (is-eq (get owner (unwrap-panic collection-info)) caller) ERR-NOT-AUTHORIZED)
    
    ;; Delete collection
    (map-delete collections { collection-id: collection-id })
    
    ;; Note: In a production system, we would also clean up all related entries
    ;; like permissions and document associations
    
    (ok true)
  )
)