-- Copyright (C) 2010 Stephan Maka <stephan@spaceboyz.net>
-- Copyright (C) 2010 John Millikin <jmillikin@gmail.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE OverloadedStrings #-}
module Network.Protocol.XMPP.Component
	( Component
	, componentJID
	, componentStreamID
	, connectComponent
	) where

import Network (connectTo)
import Text.XML.HXT.Arrow ((>>>))
import qualified Text.XML.HXT.Arrow as A
import qualified Text.XML.HXT.DOM.Interface as DOM
import qualified Text.XML.HXT.DOM.XmlNode as XN
import qualified Data.Digest.Pure.SHA as SHA
import qualified System.IO as IO
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Text.XML.LibXML.SAX as SAX

import qualified Network.Protocol.XMPP.Internal.Connections as C
import qualified Network.Protocol.XMPP.Internal.Handle as H
import qualified Network.Protocol.XMPP.Stream as S
import qualified Network.Protocol.XMPP.Internal.Stream as S
import Network.Protocol.XMPP.Internal.XML ( getTree, putTree
                                                 , element, qname
                                                 , readEventsUntil
                                                 )
import Network.Protocol.XMPP.JID (JID)

data Component = Component
	{ componentJID      :: JID
	, componentHandle   :: H.Handle
	, componentParser   :: SAX.Parser
	, componentStreamID :: T.Text
	}

instance S.Stream Component where
	getTree s = getTree (componentHandle s) (componentParser s)
	putTree s = putTree (componentHandle s)

connectComponent :: C.Server
                  -> T.Text -- ^ Password
                  -> IO Component
connectComponent server password = do
	let C.Server jid host port = server
	rawHandle <- connectTo host port
	IO.hSetBuffering rawHandle IO.NoBuffering
	let handle = H.PlainHandle rawHandle
	
	stream <- beginStream jid handle
	authenticate stream password
	return stream

beginStream :: JID -> H.Handle -> IO Component
beginStream jid h = do
	parser <- SAX.mkParser
	H.hPutBytes h $ C.xmlHeader "jabber:component:accept" jid
	events <- readEventsUntil C.startOfStream h parser
	let streamID' = case parseStreamID $ last events of
		Nothing -> error "No component stream ID defined"
		Just x -> x
	return $ Component jid h parser streamID'

parseStreamID :: SAX.Event -> Maybe T.Text
parseStreamID (SAX.BeginElement _ attrs) = sid where
	sid = case idAttrs of
		(x:_) -> Just . T.pack . SAX.attributeValue $ x
		_ -> Nothing
	idAttrs = filter (matchingName . SAX.attributeName) attrs
	matchingName n = and
		[ SAX.qnameNamespace n == "jabber:component:accept"
		, SAX.qnameLocalName n == "id"
		]
parseStreamID _ = Nothing

authenticate :: Component -> T.Text -> IO ()
authenticate stream password = do
	let bytes = buildSecret (componentStreamID stream) password
	let digest = SHA.showDigest $ SHA.sha1 $ BL.fromChunks [bytes]
	S.putTree stream $ element ("", "handshake") [] [XN.mkText digest]
	result <- S.getTree stream
	let accepted = A.runLA $
		A.getChildren
		>>> A.hasQName (qname "jabber:component:accept" "handshake")
	if null (accepted result)
		then error "Component handshake failed" -- TODO: throwIO
		else return ()

buildSecret :: T.Text -> T.Text -> B.ByteString
buildSecret sid password = bytes where
	bytes = TE.encodeUtf8 $ T.pack escaped
	escaped = DOM.attrEscapeXml $ sid' ++ password'
	sid' = T.unpack sid
	password' = T.unpack password
